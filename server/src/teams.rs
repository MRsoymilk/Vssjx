//! Durable teams and cooperative encounters; resources and receipts commit together.
use crate::{
    AppState,
    auth::{self, AuthError, Peer},
    team_rules::{Battle, MAX_MEMBERS},
};
use rand::Rng;
use axum::{
    Json,
    extract::{State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{Postgres, Row, Transaction, types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub character_id: Uuid,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub encounter_version: Option<u8>,
    pub action: String,
    #[serde(default)]
    pub operation_id: Option<Uuid>,
    #[serde(default)]
    pub target: Option<String>,
    #[serde(default)]
    pub battle_id: Option<Uuid>,
    #[serde(default)]
    pub expected_revision: Option<u64>,
    #[serde(default)]
    pub skill: Option<String>,
    #[serde(default)]
    pub ready: Option<bool>,
}
const ACTIONS: [&str; 19] = [
    "playback_done",
    "loot_roll",
    "loot_pass",
    "snapshot",
    "follow",
    "create",
    "invite",
    "accept",
    "reject",
    "cancel",
    "leave",
    "kick",
    "transfer",
    "disband",
    "ready",
    "challenge",
    "attack",
    "skill",
    "guard",
];
fn err(code: &'static str) -> AuthError {
    AuthError(StatusCode::CONFLICT, code)
}
fn db(e: sqlx::Error) -> AuthError {
    crate::observability::database_error(&e, "teams");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn target(c: &Command) -> Result<Uuid, AuthError> {
    c.target
        .as_deref()
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or(err("INVALID_TEAM_TARGET"))
}
async fn membership(
    tx: &mut Transaction<'_, Postgres>,
    id: Uuid,
) -> Result<Option<(Uuid, bool)>, AuthError> {
    sqlx::query_as("SELECT team_id,leader FROM team_members WHERE character_id=$1")
        .bind(id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(db)
}
async fn members(tx: &mut Transaction<'_, Postgres>, team: Uuid) -> Result<Vec<Uuid>, AuthError> {
    sqlx::query_scalar("SELECT character_id FROM team_members WHERE team_id=$1 ORDER BY leader DESC,joined_at,character_id").bind(team).fetch_all(&mut **tx).await.map_err(db)
}
async fn battle(
    tx: &mut Transaction<'_, Postgres>,
    team: Uuid,
) -> Result<Option<Battle>, AuthError> {
    let value: Option<DbJson<Battle>> = sqlx::query_scalar(
        "SELECT state FROM team_battles WHERE team_id=$1 ORDER BY updated_at DESC,id DESC LIMIT 1",
    )
    .bind(team)
    .fetch_optional(&mut **tx)
    .await
    .map_err(db)?;
    Ok(value.map(|v| v.0))
}
async fn save_battle(
    tx: &mut Transaction<'_, Postgres>,
    team: Uuid,
    b: &Battle,
    settle: bool,
) -> Result<(), AuthError> {
    let mut saved=b.clone();
    if settle&&b.outcome=="victory"&&b.loot_revision>=1&&saved.loot_pool.is_none(){
        let now:i64=sqlx::query_scalar("SELECT (extract(epoch FROM clock_timestamp())*1000)::bigint").fetch_one(&mut **tx).await.map_err(db)?;
        saved.loot_pool=Some(crate::pve::team_loot_pool(tx,b,now).await?);
    }
    let mut fighters = b.fighters.iter().collect::<Vec<_>>();
    fighters.sort_by_key(|f| f.id);
    for f in fighters {
        crate::pve::team_save(tx, f, b, settle).await?;
    }
    sqlx::query("INSERT INTO team_battles(id,team_id,active,state,deadline_ms) VALUES($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET active=EXCLUDED.active,state=EXCLUDED.state,deadline_ms=EXCLUDED.deadline_ms,updated_at=clock_timestamp()")
        .bind(b.id).bind(team).bind(b.active()).bind(DbJson(&saved)).bind(b.deadline_ms).execute(&mut **tx).await.map_err(db)?;
    // Readiness is the member's standing preference, cancelled explicitly or
    // when changing follow mode. Finishing an encounter must not revoke it.
    Ok(())
}
async fn save_loot(tx:&mut Transaction<'_,Postgres>,b:&mut Battle)->Result<(),AuthError>{
    if let Some(pool)=b.loot_pool.as_mut(){
        let mut indices:Vec<_>=pool.drops.iter().enumerate().filter(|(_,d)|d.resolved&&!d.delivered&&d.winner.is_some()).map(|(i,d)|(d.winner.unwrap(),i)).collect();indices.sort();
        for (winner,i) in indices{crate::pve::team_loot_award(tx,winner,&pool.drops[i].item).await?;pool.drops[i].delivered=true;pool.revision+=1;}
    }
    sqlx::query("UPDATE team_battles SET state=$2,updated_at=clock_timestamp() WHERE id=$1").bind(b.id).bind(DbJson(b)).execute(&mut **tx).await.map_err(db)?;Ok(())
}
pub(crate) async fn command(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
    body: Result<Json<Command>, JsonRejection>,
) -> Result<Json<Value>, AuthError> {
    let auth = auth::service(&state)?;
    auth.admit_team(auth::peer_ip(peer), None)?;
    let bearer = auth::bearer(&headers)?;
    let account = auth.me(bearer).await?;
    auth.admit_team(auth::peer_ip(None), Some(account.id))?;
    let Json(c) = body.map_err(|_| AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"))?;
    if (!ACTIONS.contains(&c.action.as_str()) && !matches!(c.action.as_str(), "potion" | "flee"))
        || c.encounter_version.is_some_and(|v|v!=2 || c.action!="challenge")
        || c.target.as_ref().is_some_and(|s| s.len() > 64)
        || c.skill.as_ref().is_some_and(|s| s.len() > 32)
        || c.action != "snapshot" && c.operation_id.is_none_or(|id| id.get_version_num() != 4)
    {
        return Err(AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"));
    }
    let hub = state.world.as_ref().ok_or(err("WORLD_UNAVAILABLE"))?;
    let _update = hub.team_updates.lock().await;
    let mut tx = auth.pool().begin().await.map_err(db)?;
    sqlx::query("SET LOCAL lock_timeout='3s'")
        .execute(&mut *tx)
        .await
        .map_err(db)?;
    sqlx::query("SELECT pg_advisory_xact_lock(773913019)")
        .execute(&mut *tx)
        .await
        .map_err(db)?;
    auth.authorize_in(&mut tx, bearer).await?;
    let session: Uuid = sqlx::query_scalar("SELECT id FROM sessions WHERE access_digest=$1")
        .bind(auth::token_digest(bearer)?)
        .fetch_one(&mut *tx)
        .await
        .map_err(db)?;
    let owned: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL)")
            .bind(c.character_id)
            .bind(account.id)
            .fetch_one(&mut *tx)
            .await
            .map_err(db)?;
    if !owned {
        return Err(AuthError(StatusCode::FORBIDDEN, "FORBIDDEN"));
    }
    sqlx::query("DELETE FROM team_invites WHERE expires_at<=clock_timestamp()")
        .execute(&mut *tx)
        .await
        .map_err(db)?;
    let old = membership(&mut tx, c.character_id).await?;
    let invited_team: Option<Uuid> = if matches!(c.action.as_str(), "accept" | "reject") {
        sqlx::query_scalar(
            "SELECT team_id FROM team_invites WHERE id=$1 AND target=$2 AND status='pending'",
        )
        .bind(target(&c)?)
        .bind(c.character_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(db)?
    } else {
        None
    };
    let team = old.map(|m| m.0).or(invited_team);
    let mut ids = if let Some(t) = team {
        members(&mut tx, t).await?
    } else {
        vec![]
    };
    let mut affected=ids.clone();affected.push(c.character_id);
    ids.push(c.character_id);
    if matches!(c.action.as_str(), "invite" | "kick" | "transfer") {
        ids.push(target(&c)?);
    }
    ids.sort();
    ids.dedup();
    let _gates = hub.team_guards(&ids).await;
    let now:i64=sqlx::query_scalar("SELECT (extract(epoch FROM clock_timestamp())*1000)::bigint")
        .fetch_one(&mut *tx).await.map_err(db)?;
    let mut current = if let Some(t) = team {
        battle(&mut tx, t).await?
    } else {
        None
    };
    let mut dirty = false;
    let was_active=current.as_ref().is_some_and(|b|b.active());
    if let Some(b) = current
        .as_mut()
        .filter(|b| b.active() && b.deadline_ms <= now)
    {
        let actor = b.fighters[b.turn].id;
        b.expire(now,rand::random::<u8>() as i32 % 100);
        save_battle(&mut tx, team.unwrap(), b, !b.active()).await?;
        crate::security::append(&mut *tx,crate::security::Event{account:None,character:Some(actor),session:None,operation:None,action:"team.timeout",outcome:"accepted",code:if b.active(){"AUTO_GUARD"}else{"BATTLE_ENDED"},details:json!({"battle_id":b.id,"revision":b.revision,"requested_by":c.character_id})}).await.map_err(db)?;
        dirty = true;
    }
    if let Some(b)=current.as_mut().filter(|b|b.loot_pool.as_ref().is_some_and(|p|p.pending()&&p.deadline_ms<=now)){
        b.loot_pool.as_mut().unwrap().resolve(now);save_loot(&mut tx,b).await?;dirty=true;
        crate::security::append(&mut *tx,crate::security::Event{account:None,character:Some(c.character_id),session:None,operation:None,action:"team.loot_timeout",outcome:"accepted",code:"OK",details:json!({"battle_id":b.id,"loot":b.loot_pool})}).await.map_err(db)?;
    }
    let mut reservation = None;
    let mut code = "OK".to_owned();
    let mut replayed = false;
    if c.action != "snapshot" {
        let digest = Sha256::digest(serde_json::to_vec(&c).unwrap()).to_vec();
        let prior=sqlx::query("SELECT request_digest,result FROM team_receipts WHERE character_id=$1 AND operation_id=$2").bind(c.character_id).bind(c.operation_id).fetch_optional(&mut *tx).await.map_err(db)?;
        if let Some(r) = prior {
            if r.get::<Vec<u8>, _>("request_digest") != digest {
                return Err(AuthError(StatusCode::CONFLICT, "IDEMPOTENCY_CONFLICT"));
            }
            code = r.get::<DbJson<Value>, _>("result").0["code"]
                .as_str()
                .unwrap_or("TEAM_FAILED")
                .into();
            replayed = true;
        } else {
            sqlx::query("SAVEPOINT team_business")
                .execute(&mut *tx)
                .await
                .map_err(db)?;
            match apply(&mut tx, hub, &c, session, now, &mut reservation).await {
                Ok(changed) => {
                    dirty |= changed;
                }
                Err(e) if e.0 != StatusCode::SERVICE_UNAVAILABLE => {
                    sqlx::query("ROLLBACK TO SAVEPOINT team_business")
                        .execute(&mut *tx)
                        .await
                        .map_err(db)?;
                    reservation = None;
                    code = e.1.into();
                }
                Err(e) => return Err(e),
            }
            sqlx::query("INSERT INTO team_receipts(character_id,operation_id,request_digest,result) VALUES($1,$2,$3,$4)").bind(c.character_id).bind(c.operation_id).bind(digest).bind(DbJson(json!({"code":code}))).execute(&mut *tx).await.map_err(db)?;
        }
        crate::security::append(
            &mut *tx,
            crate::security::Event {
                account: Some(account.id),
                character: Some(c.character_id),
                session: Some(session),
                operation: c.operation_id,
                action: &format!("team.{}", c.action),
                outcome: if replayed {
                    "replayed"
                } else if code == "OK" {
                    "accepted"
                } else {
                    "rejected"
                },
                code: &code,
                details: json!({"target":c.target,"battle_id":c.battle_id,"ready":c.ready}),
            },
        )
        .await
        .map_err(db)?;
    }
    let response = snapshot(&mut tx, c.character_id, &hub.online_characters(), now).await?;
    let final_team = membership(&mut tx, c.character_id)
        .await?
        .map(|v| v.0)
        .or(team);
    let final_battle = if let Some(t) = final_team {
        battle(&mut tx, t).await?
    } else {
        None
    };
    if let Some(t) = final_team {
        affected.extend(members(&mut tx, t).await?);
    }
    if let Some(r) = reservation {
        // A lost commit acknowledgement is ambiguous: keep the movement fence
        // until a later snapshot/retry resolves the durable battle state.
        r.commit();
    }
    let roster=if let Some(t)=final_team {crate::world::team_bridge::roster(&mut tx,t).await?}else{vec![]};
    tx.commit().await.map_err(db)?;
    hub.team_roster_sync(&affected,roster);
    hub.team_sync(&affected, final_battle.as_ref().filter(|b|b.active()||was_active), dirty);
    Ok(Json(
        json!({"version":"team-v1","character_id":c.character_id,"operation_id":c.operation_id,"ok":code=="OK","code":code,"replayed":replayed,"server_time_ms":now,"state":response}),
    ))
}
async fn apply(
    tx: &mut Transaction<'_, Postgres>,
    hub: &Arc<crate::world::WorldHub>,
    c: &Command,
    session: Uuid,
    now: i64,
    reserve: &mut Option<crate::world::TeamReservation>,
) -> Result<bool, AuthError> {
    let me = c.character_id;
    let mut own_membership = membership(tx, me).await?;
    let context = hub.team_context(me)?;
    if context.session != session {
        return Err(err("SESSION_REPLACED"));
    }
    if let Some((t,_))=own_membership{
        if let Some(mut b)=battle(tx,t).await?.filter(|b|!b.active()&&b.loot_pool.is_some()){
            if matches!(c.action.as_str(),"loot_roll"|"loot_pass"){
                if c.battle_id!=Some(b.id)||c.skill.is_some()||c.ready.is_some()||c.expected_revision.is_none_or(|r|r>b.loot_pool.as_ref().unwrap().revision){return Err(err("STALE_BATTLE"));}
                let id=target(c)?;
                let roll=if c.action=="loot_roll"{Some(rand::thread_rng().gen_range(1..=100))}else{None};
                b.loot_pool.as_mut().unwrap().choose(me,id,roll,now).map_err(err)?;save_loot(tx,&mut b).await?;return Ok(true);
            }
            if b.loot_pool.as_ref().unwrap().pending(){return Err(err("TEAM_LOOT_PENDING"));}
        }
    }
    if matches!(c.action.as_str(),"loot_roll"|"loot_pass"){return Err(err("TEAM_LOOT_NOT_FOUND"));}
    if let Some((t, _)) = own_membership {
        if let Some(b) = battle(tx, t).await?.filter(|b| b.active()) {
            if !matches!(
                c.action.as_str(),
                "attack" | "skill" | "guard" | "potion" | "flee" | "playback_done"
            ) {
                return Err(err("TEAM_BATTLE_ACTIVE"));
            }
            if c.battle_id != Some(b.id) || !c.expected_revision.is_some_and(|r|r>=b.round_revision&&r<=b.revision) {
                return Err(err("STALE_BATTLE"));
            }
            let mut b = b;
            if c.action == "playback_done" {
                if c.target.is_some() || c.skill.is_some() || c.ready.is_some() {
                    return Err(err("INVALID_TEAM_COMMAND"));
                }
                b.acknowledge_playback(me, c.expected_revision.unwrap(), now).map_err(err)?;
                // Presentation receipts must not rewrite character resources,
                // issue rewards or advance movement/character revisions.
                sqlx::query("UPDATE team_battles SET state=$2,deadline_ms=$3,updated_at=clock_timestamp() WHERE id=$1")
                    .bind(b.id).bind(DbJson(&b)).bind(b.deadline_ms).execute(&mut **tx).await.map_err(db)?;
                return Ok(false);
            } else if c.action == "flee" {
                if !own_membership.unwrap().1 {
                    return Err(err("TEAM_LEADER_REQUIRED"));
                }
                b.finish("fled");
                b.revision += 1;
            } else {
                b.act(
                    me,
                    &c.action,
                    c.target.as_deref(),
                    c.skill.as_deref(),
                    now,
                    rand::random::<u8>() as i32 % 100,
                )
                .map_err(err)?;
            }
            save_battle(tx, t, &b, !b.active()).await?;
            return Ok(true);
        }
    }
    if matches!(
        c.action.as_str(),
        "attack" | "skill" | "guard" | "potion" | "flee" | "playback_done"
    ) {
        return Err(err("NO_ACTIVE_BATTLE"));
    }
    if c.battle_id.is_some() || c.expected_revision.is_some() || c.skill.is_some() {
        return Err(err("INVALID_TEAM_COMMAND"));
    }
    if c.action == "create" || c.action == "invite" && own_membership.is_none() {
        if own_membership.is_some() {
            return Err(err("ALREADY_IN_TEAM"));
        }
        let id = Uuid::new_v4();
        sqlx::query("INSERT INTO teams(id) VALUES($1)")
            .bind(id)
            .execute(&mut **tx)
            .await
            .map_err(db)?;
        sqlx::query("INSERT INTO team_members(character_id,team_id,leader) VALUES($1,$2,TRUE)")
            .bind(me)
            .bind(id)
            .execute(&mut **tx)
            .await
            .map_err(db)?;
        own_membership = Some((id, true));
        if c.action == "create" {
            return Ok(false);
        }
    }
    if matches!(c.action.as_str(), "accept" | "reject") {
        let invite = target(c)?;
        let row=sqlx::query("SELECT team_id FROM team_invites WHERE id=$1 AND target=$2 AND status='pending' AND expires_at>clock_timestamp()").bind(invite).bind(me).fetch_optional(&mut **tx).await.map_err(db)?.ok_or(err("TEAM_INVITE_EXPIRED"))?;
        let team: Uuid = row.get("team_id");
        if c.action == "reject" {
            sqlx::query("UPDATE team_invites SET status='rejected',expires_at=clock_timestamp()+interval '5 minutes' WHERE id=$1").bind(invite).execute(&mut **tx).await.map_err(db)?;
            return Ok(false);
        }
        if own_membership.is_some() {
            return Err(err("ALREADY_IN_TEAM"));
        }
        if battle(tx, team).await?.is_some_and(|b| b.active()) {
            return Err(err("TEAM_BATTLE_ACTIVE"));
        }
        if members(tx, team).await?.len() >= MAX_MEMBERS {
            return Err(err("TEAM_FULL"));
        }
        sqlx::query("INSERT INTO team_members(character_id,team_id) VALUES($1,$2)")
            .bind(me)
            .bind(team)
            .execute(&mut **tx)
            .await
            .map_err(db)?;
        sqlx::query("DELETE FROM team_invites WHERE target=$1")
            .bind(me)
            .execute(&mut **tx)
            .await
            .map_err(db)?;
        return Ok(false);
    }
    let (team, leader) = own_membership.ok_or(err("NOT_IN_TEAM"))?;
    if c.action == "follow" {
        if leader {return Err(err("TEAM_MEMBER_REQUIRED"));}
        sqlx::query("UPDATE team_members SET following=$2,ready=FALSE WHERE character_id=$1")
            .bind(me).bind(c.ready.ok_or(err("INVALID_TEAM_COMMAND"))?).execute(&mut **tx).await.map_err(db)?;
        return Ok(false);
    }
    if c.action == "ready" {
        if context.moving {
            return Err(err("TEAM_NOT_READY"));
        }
        sqlx::query("UPDATE team_members SET ready=$2 WHERE character_id=$1")
            .bind(me)
            .bind(c.ready.ok_or(err("INVALID_TEAM_COMMAND"))?)
            .execute(&mut **tx)
            .await
            .map_err(db)?;
        return Ok(false);
    }
    if c.action == "leave" {
        if leader && members(tx, team).await?.len() > 1 {
            return Err(err("TEAM_LEADER_MUST_TRANSFER"));
        }
        if leader {
            sqlx::query("DELETE FROM teams WHERE id=$1")
                .bind(team)
                .execute(&mut **tx)
                .await
                .map_err(db)?;
        } else {
            sqlx::query("DELETE FROM team_members WHERE character_id=$1")
                .bind(me)
                .execute(&mut **tx)
                .await
                .map_err(db)?;
        }
        return Ok(false);
    }
    if !leader {
        return Err(err("TEAM_LEADER_REQUIRED"));
    }
    match c.action.as_str() {
        "invite" => {
            let other = target(c)?;
            if other == me {
                return Err(err("SELF_TARGET"));
            }
            hub.team_context(other)?;
            if membership(tx, other).await?.is_some() {
                return Err(err("ALREADY_IN_TEAM"));
            }
            if members(tx, team).await?.len() >= MAX_MEMBERS {
                return Err(err("TEAM_FULL"));
            }
            let prior: Option<String> = sqlx::query_scalar(
                "SELECT status FROM team_invites WHERE team_id=$1 AND target=$2",
            )
            .bind(team)
            .bind(other)
            .fetch_optional(&mut **tx)
            .await
            .map_err(db)?;
            if let Some(status) = prior {
                return Err(err(if status == "rejected" {
                    "TEAM_INVITE_COOLDOWN"
                } else {
                    "TEAM_INVITE_PENDING"
                }));
            }
            let count: i64 =
                sqlx::query_scalar("SELECT count(*) FROM team_invites WHERE team_id=$1")
                    .bind(team)
                    .fetch_one(&mut **tx)
                    .await
                    .map_err(db)?;
            if count >= 10 {
                return Err(err("TEAM_INVITE_LIMIT"));
            }
            let received:i64=sqlx::query_scalar("SELECT count(*) FROM team_invites WHERE target=$1 AND status='pending'").bind(other).fetch_one(&mut **tx).await.map_err(db)?;
            if received>=10{return Err(err("TEAM_INVITE_LIMIT"));}
            sqlx::query("INSERT INTO team_invites(id,team_id,target) VALUES($1,$2,$3)")
                .bind(Uuid::new_v4())
                .bind(team)
                .bind(other)
                .execute(&mut **tx)
                .await
                .map_err(db)?;
        }
        "cancel" => {
            sqlx::query("DELETE FROM team_invites WHERE id=$1 AND team_id=$2")
                .bind(target(c)?)
                .bind(team)
                .execute(&mut **tx)
                .await
                .map_err(db)?;
        }
        "disband" => {
            sqlx::query("DELETE FROM teams WHERE id=$1")
                .bind(team)
                .execute(&mut **tx)
                .await
                .map_err(db)?;
        }
        "kick" | "transfer" => {
            let other = target(c)?;
            if other == me {
                return Err(err("SELF_TARGET"));
            }
            if membership(tx, other).await?.is_none_or(|v| v.0 != team) {
                return Err(err("TEAM_MEMBER_NOT_FOUND"));
            }
            if c.action == "kick" {
                sqlx::query("DELETE FROM team_members WHERE character_id=$1")
                    .bind(other)
                    .execute(&mut **tx)
                    .await
                    .map_err(db)?;
            } else {
                sqlx::query("UPDATE team_members SET leader=FALSE WHERE character_id=$1")
                    .bind(me)
                    .execute(&mut **tx)
                    .await
                    .map_err(db)?;
                sqlx::query("UPDATE team_members SET leader=TRUE WHERE character_id=$1")
                    .bind(other)
                    .execute(&mut **tx)
                    .await
                    .map_err(db)?;
            }
        }
        "challenge" => {
            // Membership survives disconnects; only online followers join a new
            // encounter. Never load, reserve, charge or reward absent members.
            let rows = sqlx::query("SELECT character_id,ready,following FROM team_members WHERE team_id=$1 ORDER BY leader DESC,joined_at,character_id")
                .bind(team).fetch_all(&mut **tx).await.map_err(db)?;
            let mut ids = vec![];
            let mut contexts = vec![];
            for row in rows {
                let id: Uuid = row.get("character_id");
                if id != me && !row.get::<bool, _>("following") {
                    continue;
                }
                let member = match hub.team_context(id) {
                    Ok(member) => member,
                    Err(e) if id != me && e.1 == "TEAM_PLAYER_OFFLINE" => continue,
                    Err(e) => return Err(e),
                };
                // Choosing the encounter is the leader's confirmation. Online
                // followers must still explicitly prepare; do not omit them.
                if id != me && !row.get::<bool, _>("ready") {
                    return Err(err("TEAM_NOT_READY"));
                }
                ids.push(id);
                contexts.push(member);
            }
            if contexts.iter().any(|p| {
                p.map_id != context.map_id
                    || (p.cell[0] - context.cell[0]).abs() + (p.cell[1] - context.cell[1]).abs() > 8
                    || p.moving
            }) {
                return Err(err("TEAM_NOT_TOGETHER"));
            }
            let enemy = hub.team_enemy(me, c.target.as_deref().ok_or(err("INVALID_RESIDENT"))?)?;
            *reserve = Some(hub.team_reserve(&ids));
            let mut fighters = vec![];
            let mut unavailable = std::collections::HashSet::new();
            // UUID row-lock order matches other multi-character mutations.
            let mut sorted = contexts.iter().collect::<Vec<_>>();
            sorted.sort_by_key(|v| v.character);
            for ctx in sorted {
                let (f, cooldown) = crate::pve::team_fighter(tx, ctx).await?;
                fighters.push(f);
                unavailable.extend(cooldown);
            }
            fighters.sort_by_key(|f| ids.iter().position(|id| *id == f.id).unwrap());
            if unavailable.contains(&enemy.id) {
                return Err(err("MONSTER_RESPAWNING"));
            }
            let pool: Vec<_> = crate::population::definitions_for(&context.map_id)
                .into_iter()
                .filter(|e| {
                    e.kind == enemy.kind && e.id != enemy.id
                        && e.level <= enemy.level + 3
                        && !unavailable.contains(&e.id)
                })
                .collect();
            let mut sources = vec![enemy.clone()];
            let n = if ids.len() == 1 {
                if enemy.kind=="boss"&&pool.is_empty(){1}else{crate::monster_combat::solo_count(rand::thread_rng().gen_range(0..100))}
            } else {
                (ids.len() + usize::from(rand::random::<bool>())).min(5)
            };
            for i in 1..n {
                sources.push(pool.get((i-1) % pool.len().max(1)).unwrap_or(&enemy).clone());
            }
            let elite=crate::pve::team_hunt(tx,&fighters.iter().map(|f|f.id).collect::<Vec<_>>(),&context.map_id,&enemy.art).await?;
            if elite && c.encounter_version!=Some(2){return Err(err("CLIENT_UPDATE_REQUIRED"));}
            let mut b = Battle::new(context.map_id, fighters, sources, now);
            if elite {b.empower_hunt();}
            save_battle(tx, team, &b, false).await?;
            return Ok(true);
        }
        _ => return Err(err("INVALID_TEAM_COMMAND")),
    }
    Ok(false)
}
async fn snapshot(
    tx: &mut Transaction<'_, Postgres>,
    me: Uuid,
    online: &std::collections::HashSet<Uuid>,
    now: i64,
) -> Result<Value, AuthError> {
    let team = if let Some((id, leader)) = membership(tx, me).await? {
        let rows=sqlx::query("SELECT c.id,c.display_name,c.job,c.gender,c.level,c.map_id,m.leader,m.ready,m.following FROM team_members m JOIN characters c ON c.id=m.character_id WHERE m.team_id=$1 ORDER BY m.leader DESC,m.joined_at,c.id").bind(id).fetch_all(&mut **tx).await.map_err(db)?;
        let members:Vec<_>=rows.into_iter().map(|r|{let id:Uuid=r.get("id");json!({"id":id,"display_name":r.get::<String,_>("display_name"),"job":r.get::<i16,_>("job"),"gender":r.get::<i16,_>("gender"),"level":r.get::<i32,_>("level"),"map_id":r.get::<String,_>("map_id"),"leader":r.get::<bool,_>("leader"),"ready":r.get::<bool,_>("ready"),"following":r.get::<bool,_>("following"),"online":online.contains(&id)})}).collect();
        let current = battle(tx, id).await?;
        let battle_active = current.as_ref().is_some_and(|b| b.active());
        let b = current.filter(|b| b.fighters.iter().any(|f| f.id == me));
        let rows = if leader {
            sqlx::query("SELECT i.id,c.display_name FROM team_invites i JOIN characters c ON c.id=i.target WHERE i.team_id=$1 AND i.status='pending' ORDER BY i.expires_at,i.id").bind(id).fetch_all(&mut **tx).await.map_err(db)?
        } else {
            vec![]
        };
        let outgoing: Vec<_> = rows
            .iter()
            .map(|r| json!({"id":r.get::<Uuid,_>("id"),"name":r.get::<String,_>("display_name")}))
            .collect();
        crate::attributes::public_battle(json!({"id":id,"leader":leader,"members":members,"battle":b,"battle_active":battle_active,"outgoing":outgoing}))
    } else {
        Value::Null
    };
    let invites=sqlx::query("SELECT i.id,c.display_name,(extract(epoch FROM i.expires_at)*1000)::bigint AS expires_ms FROM team_invites i JOIN team_members m ON m.team_id=i.team_id AND m.leader JOIN characters c ON c.id=m.character_id WHERE i.target=$1 AND i.status='pending' ORDER BY i.expires_at,i.id LIMIT 10").bind(me).fetch_all(&mut **tx).await.map_err(db)?;
    let incoming:Vec<_>=invites.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"name":r.get::<String,_>("display_name"),"remaining_ms":(r.get::<i64,_>("expires_ms")-now).max(0)})).collect();
    Ok(json!({"team":team,"incoming":incoming}))
}
