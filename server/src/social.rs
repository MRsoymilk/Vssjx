//! Public character cards, consensual friendships, and durable guild membership.
//! One short social-only transaction lock orders capacity checks and role transfers;
//! gameplay/character rows are never updated by these commands.
use crate::{
    AppState,
    auth::{self, AuthError, Peer},
};
use axum::{
    Json,
    extract::{State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{PgConnection, Row, types::Json as DbJson};
use std::{
    collections::{BTreeMap, HashSet},
    sync::Arc,
};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Snapshot,
    Profile,
    Find,
    GuildBrowse,
    FriendRequest,
    FriendAccept,
    FriendReject,
    FriendRemove,
    GuildCreate,
    GuildApply,
    GuildCancel,
    GuildApprove,
    GuildReject,
    GuildKick,
    GuildTransfer,
    GuildLeave,
    GuildDisband,
    GuildAnnounce,
}
impl Action {
    fn read(self) -> bool {
        matches!(
            self,
            Self::Snapshot | Self::Profile | Self::Find | Self::GuildBrowse
        )
    }
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub character_id: Uuid,
    pub action: Action,
    #[serde(default)]
    pub operation_id: Option<Uuid>,
    #[serde(default)]
    pub target: Option<Uuid>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub text: String,
}
fn database(e: sqlx::Error) -> AuthError {
    crate::observability::database_error(&e, "social");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn invalid() -> AuthError {
    AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST")
}

pub(crate) async fn command(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
    body: Result<Json<Command>, JsonRejection>,
) -> Result<Json<Value>, AuthError> {
    let auth = auth::service(&state)?;
    auth.admit_social_peer(auth::peer_ip(peer))?;
    let bearer = auth::bearer(&headers)?;
    let account = auth.me(bearer).await?;
    auth.admit_social(account.id)?;
    let Json(c) = body.map_err(|_| invalid())?;
    if c.name.len() > 128
        || c.text.len() > 512
        || (!c.action.read()
            && c.operation_id.is_none_or(|id| {
                id.get_version_num() != 4 || id.get_variant() != uuid::Variant::RFC4122
            }))
    {
        return Err(invalid());
    }
    let mut tx = auth.pool().begin().await.map_err(database)?;
    // Timeout bounds contention instead of allowing an unbounded waiter queue.
    sqlx::query("SET LOCAL lock_timeout='2s'")
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    sqlx::query("SELECT pg_advisory_xact_lock(773913018)")
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    auth.authorize_in(&mut tx, bearer).await?;
    let owned: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL)")
            .bind(c.character_id)
            .bind(account.id)
            .fetch_one(&mut *tx)
            .await
            .map_err(database)?;
    if !owned {
        return Err(AuthError(StatusCode::FORBIDDEN, "FORBIDDEN"));
    }
    let online = state
        .world
        .as_ref()
        .map_or_else(HashSet::new, |w| w.online_characters());
    let mut replayed = false;
    let mut code = "OK";
    let mut profile = Value::Null;
    if c.action.read() {
        if matches!(c.action, Action::Profile | Action::Find) {
            let target = if matches!(c.action, Action::Find) {
                let (_, key) = crate::characters::canonical_name(&c.name)?;
                sqlx::query_scalar("SELECT id FROM characters WHERE name_key=$1 AND deleted_at IS NULL")
                    .bind(key)
                    .fetch_optional(&mut *tx)
                    .await
                    .map_err(database)?
            } else {
                c.target
            };
            if let Some(id) = target {
                profile = public_profile(&mut tx, id, &online).await?;
            }
            if profile.is_null() {
                code = "PLAYER_NOT_FOUND";
            }
        }
    } else {
        let digest = Sha256::digest(serde_json::to_vec(&c).expect("typed social command")).to_vec();
        let prior=sqlx::query("SELECT request_digest,result FROM social_receipts WHERE character_id=$1 AND operation_id=$2")
            .bind(c.character_id).bind(c.operation_id).fetch_optional(&mut *tx).await.map_err(database)?;
        if let Some(row) = prior {
            if row.get::<Vec<u8>, _>("request_digest") != digest {
                return Err(AuthError(StatusCode::CONFLICT, "IDEMPOTENCY_CONFLICT"));
            }
            let result = row.get::<DbJson<Value>, _>("result").0;
            code = result["code"]
                .as_str()
                .and_then(known_code)
                .unwrap_or("SOCIAL_FAILED");
            replayed = true;
        } else {
            code = apply(&mut tx, &c).await?;
            sqlx::query("INSERT INTO social_receipts(character_id,operation_id,request_digest,result) VALUES($1,$2,$3,$4)")
                .bind(c.character_id).bind(c.operation_id).bind(digest).bind(DbJson(json!({"code":code}))).execute(&mut *tx).await.map_err(database)?;
        }
        let action = format!(
            "social.{}",
            serde_json::to_value(c.action).unwrap().as_str().unwrap()
        );
        crate::security::append(
            &mut *tx,
            crate::security::Event {
                account: Some(account.id),
                character: Some(c.character_id),
                session: None,
                operation: c.operation_id,
                action: &action,
                outcome: if replayed {
                    "replayed"
                } else if code == "OK" {
                    "accepted"
                } else {
                    "rejected"
                },
                code,
                details: json!({"target":c.target}),
            },
        )
        .await
        .map_err(database)?;
    }
    let search = if matches!(c.action, Action::GuildBrowse) {
        c.name.trim()
    } else {
        ""
    };
    let snapshot = snapshot(&mut tx, c.character_id, &online, search).await?;
    tx.commit().await.map_err(database)?;
    Ok(Json(
        json!({"version":"social-v1","character_id":c.character_id,"operation_id":c.operation_id,
        "ok":code=="OK","code":code,"replayed":replayed,"state":snapshot,"profile":profile}),
    ))
}
fn known_code(s: &str) -> Option<&'static str> {
    [
        "OK",
        "PLAYER_NOT_FOUND",
        "SELF_TARGET",
        "FRIEND_LIMIT",
        "REQUEST_PENDING",
        "ALREADY_FRIENDS",
        "FRIEND_COOLDOWN",
        "REQUEST_NOT_FOUND",
        "FORBIDDEN",
        "INVALID_NAME",
        "GUILD_NAME_TAKEN",
        "ALREADY_IN_GUILD",
        "GUILD_NOT_FOUND",
        "GUILD_FULL",
        "APPLICATION_LIMIT",
        "ALREADY_APPLIED",
        "NOT_IN_GUILD",
        "LEADER_REQUIRED",
        "LEADER_MUST_TRANSFER",
        "MEMBER_NOT_FOUND",
        "INVALID_TEXT",
    ]
    .into_iter()
    .find(|v| *v == s)
}
async fn count(db: &mut PgConnection, sql: &str, id: Uuid) -> Result<i64, AuthError> {
    sqlx::query_scalar(sql)
        .bind(id)
        .fetch_one(db)
        .await
        .map_err(database)
}
async fn member(db: &mut PgConnection, id: Uuid) -> Result<Option<(Uuid, String)>, AuthError> {
    sqlx::query_as("SELECT guild_id,role FROM guild_members WHERE character_id=$1")
        .bind(id)
        .fetch_optional(db)
        .await
        .map_err(database)
}
async fn apply(db: &mut PgConnection, c: &Command) -> Result<&'static str, AuthError> {
    use Action::*;
    let me = c.character_id;
    if matches!(
        c.action,
        FriendRequest | FriendAccept | FriendReject | FriendRemove
    ) {
        let Some(other) = c.target else {
            return Ok("PLAYER_NOT_FOUND");
        };
        if other == me {
            return Ok("SELF_TARGET");
        }
        if count(db,"SELECT count(*) FROM characters c JOIN accounts a ON a.id=c.account_id WHERE c.id=$1 AND c.deleted_at IS NULL AND NOT a.disabled",other).await?==0{return Ok("PLAYER_NOT_FOUND");}
        let (lo, hi) = if me < other { (me, other) } else { (other, me) };
        let row=sqlx::query("SELECT requester_id,status,updated_at>clock_timestamp()-interval '5 minutes' AS cooling FROM friendships WHERE low_id=$1 AND high_id=$2")
            .bind(lo).bind(hi).fetch_optional(&mut *db).await.map_err(database)?;
        if matches!(c.action, FriendRequest) {
            if let Some(r) = &row {
                match r.get::<&str, _>("status") {
                    "accepted" => return Ok("ALREADY_FRIENDS"),
                    "pending" => return Ok("REQUEST_PENDING"),
                    _ => {
                        if r.get::<bool, _>("cooling") {
                            return Ok("FRIEND_COOLDOWN");
                        }
                    }
                }
            }
            for id in [me, other] {
                if count(db,"SELECT count(*) FROM friendships WHERE (low_id=$1 OR high_id=$1) AND status IN ('pending','accepted')",id).await?>=100{return Ok("FRIEND_LIMIT");}
            }
            sqlx::query("INSERT INTO friendships(low_id,high_id,requester_id,status) VALUES($1,$2,$3,'pending') ON CONFLICT(low_id,high_id) DO UPDATE SET requester_id=$3,status='pending',updated_at=clock_timestamp()")
                .bind(lo).bind(hi).bind(me).execute(&mut *db).await.map_err(database)?;
        } else {
            let Some(r) = row else {
                return Ok("REQUEST_NOT_FOUND");
            };
            let status = r.get::<&str, _>("status");
            let sender: Uuid = r.get("requester_id");
            if matches!(c.action, FriendAccept | FriendReject) {
                if status != "pending" {
                    return Ok("REQUEST_NOT_FOUND");
                }
                if sender == me {
                    return Ok("FORBIDDEN");
                }
                sqlx::query("UPDATE friendships SET status=$3,updated_at=clock_timestamp() WHERE low_id=$1 AND high_id=$2")
                    .bind(lo).bind(hi).bind(if matches!(c.action,FriendAccept){"accepted"}else{"rejected"}).execute(&mut *db).await.map_err(database)?;
            } else {
                if status != "accepted" && !(status == "pending" && sender == me) {
                    return Ok("FORBIDDEN");
                }
                sqlx::query("DELETE FROM friendships WHERE low_id=$1 AND high_id=$2")
                    .bind(lo)
                    .bind(hi)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
            }
        }
        return Ok("OK");
    }
    let membership = member(db, me).await?;
    if matches!(c.action, GuildCreate) {
        if membership.is_some() {
            return Ok("ALREADY_IN_GUILD");
        }
        let Ok((name, key)) = crate::characters::canonical_name(&c.name) else {
            return Ok("INVALID_NAME");
        };
        // Guild disbanding deletes the row; only characters use deleted_at.
        if sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM guilds WHERE name_key=$1)")
            .bind(&key)
            .fetch_one(&mut *db)
            .await
            .map_err(database)?
        {
            return Ok("GUILD_NAME_TAKEN");
        }
        let id = Uuid::new_v4();
        sqlx::query("INSERT INTO guilds(id,name,name_key) VALUES($1,$2,$3)")
            .bind(id)
            .bind(name)
            .bind(key)
            .execute(&mut *db)
            .await
            .map_err(database)?;
        sqlx::query("INSERT INTO guild_members(character_id,guild_id,role) VALUES($1,$2,'leader')")
            .bind(me)
            .bind(id)
            .execute(&mut *db)
            .await
            .map_err(database)?;
        sqlx::query("DELETE FROM guild_applications WHERE character_id=$1")
            .bind(me)
            .execute(&mut *db)
            .await
            .map_err(database)?;
        return Ok("OK");
    }
    if matches!(c.action, GuildApply | GuildCancel) {
        if membership.is_some() {
            return Ok("ALREADY_IN_GUILD");
        }
        let Some(id) = c.target else {
            return Ok("GUILD_NOT_FOUND");
        };
        if count(db, "SELECT count(*) FROM guilds WHERE id=$1", id).await? == 0 {
            return Ok("GUILD_NOT_FOUND");
        }
        if matches!(c.action, GuildCancel) {
            sqlx::query("DELETE FROM guild_applications WHERE character_id=$1 AND guild_id=$2")
                .bind(me)
                .bind(id)
                .execute(&mut *db)
                .await
                .map_err(database)?;
        } else {
            if count(
                db,
                "SELECT count(*) FROM guild_members WHERE guild_id=$1",
                id,
            )
            .await?
                >= 50
            {
                return Ok("GUILD_FULL");
            }
            if sqlx::query_scalar::<_,bool>("SELECT EXISTS(SELECT 1 FROM guild_applications WHERE guild_id=$1 AND character_id=$2)").bind(id).bind(me).fetch_one(&mut *db).await.map_err(database)?{return Ok("ALREADY_APPLIED");}
            if count(
                db,
                "SELECT count(*) FROM guild_applications WHERE character_id=$1",
                me,
            )
            .await?
                >= 10
                || count(
                    db,
                    "SELECT count(*) FROM guild_applications WHERE guild_id=$1",
                    id,
                )
                .await?
                    >= 100
            {
                return Ok("APPLICATION_LIMIT");
            }
            sqlx::query("INSERT INTO guild_applications(guild_id,character_id) VALUES($1,$2)")
                .bind(id)
                .bind(me)
                .execute(&mut *db)
                .await
                .map_err(database)?;
        }
        return Ok("OK");
    }
    let Some((guild, role)) = membership else {
        return Ok("NOT_IN_GUILD");
    };
    if matches!(c.action, GuildLeave) {
        if role == "leader" {
            return Ok("LEADER_MUST_TRANSFER");
        }
        sqlx::query("DELETE FROM guild_members WHERE character_id=$1")
            .bind(me)
            .execute(&mut *db)
            .await
            .map_err(database)?;
        return Ok("OK");
    }
    if role != "leader" {
        return Ok("LEADER_REQUIRED");
    }
    match c.action {
        GuildDisband => {
            sqlx::query("DELETE FROM guilds WHERE id=$1")
                .bind(guild)
                .execute(&mut *db)
                .await
                .map_err(database)?;
        }
        GuildAnnounce => {
            if c.text.chars().count() > 120 || c.text.chars().any(|v| v.is_control()) {
                return Ok("INVALID_TEXT");
            }
            sqlx::query("UPDATE guilds SET announcement=$2 WHERE id=$1")
                .bind(guild)
                .bind(c.text.trim())
                .execute(&mut *db)
                .await
                .map_err(database)?;
        }
        GuildApprove | GuildReject => {
            let Some(target) = c.target else {
                return Ok("PLAYER_NOT_FOUND");
            };
            let pending:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM guild_applications WHERE guild_id=$1 AND character_id=$2)").bind(guild).bind(target).fetch_one(&mut *db).await.map_err(database)?;
            if !pending {
                return Ok("REQUEST_NOT_FOUND");
            }
            if matches!(c.action, GuildApprove) {
                if member(db, target).await?.is_some() {
                    return Ok("ALREADY_IN_GUILD");
                }
                if count(
                    db,
                    "SELECT count(*) FROM guild_members WHERE guild_id=$1",
                    guild,
                )
                .await?
                    >= 50
                {
                    return Ok("GUILD_FULL");
                }
                sqlx::query(
                    "INSERT INTO guild_members(character_id,guild_id,role) VALUES($1,$2,'member')",
                )
                .bind(target)
                .bind(guild)
                .execute(&mut *db)
                .await
                .map_err(database)?;
                sqlx::query("DELETE FROM guild_applications WHERE character_id=$1")
                    .bind(target)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
            } else {
                sqlx::query("DELETE FROM guild_applications WHERE guild_id=$1 AND character_id=$2")
                    .bind(guild)
                    .bind(target)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
            }
        }
        GuildKick | GuildTransfer => {
            let Some(target) = c.target else {
                return Ok("MEMBER_NOT_FOUND");
            };
            if target == me {
                return Ok("SELF_TARGET");
            }
            if member(db, target).await?.is_none_or(|m| m.0 != guild) {
                return Ok("MEMBER_NOT_FOUND");
            }
            if matches!(c.action, GuildKick) {
                sqlx::query("DELETE FROM guild_members WHERE character_id=$1")
                    .bind(target)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
            } else {
                sqlx::query("UPDATE guild_members SET role='member' WHERE character_id=$1")
                    .bind(me)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
                sqlx::query("UPDATE guild_members SET role='leader' WHERE character_id=$1")
                    .bind(target)
                    .execute(&mut *db)
                    .await
                    .map_err(database)?;
            }
        }
        _ => return Err(invalid()),
    }
    Ok("OK")
}

async fn people(
    db: &mut PgConnection,
    sql: &str,
    id: Uuid,
    online: &HashSet<Uuid>,
) -> Result<Vec<Value>, AuthError> {
    let rows = sqlx::query(sql)
        .bind(id)
        .fetch_all(db)
        .await
        .map_err(database)?;
    Ok(rows.into_iter().map(|r|{let id:Uuid=r.get("id");json!({"id":id,"display_name":r.get::<String,_>("display_name"),"job":r.get::<i16,_>("job"),"gender":r.get::<i16,_>("gender"),"level":r.get::<i32,_>("level"),"online":online.contains(&id)})}).collect())
}
async fn snapshot(
    db: &mut PgConnection,
    me: Uuid,
    online: &HashSet<Uuid>,
    search: &str,
) -> Result<Value, AuthError> {
    let friends=people(db,"SELECT c.id,c.display_name,c.job,c.gender,c.level FROM friendships f JOIN characters c ON c.id=CASE WHEN f.low_id=$1 THEN f.high_id ELSE f.low_id END WHERE (f.low_id=$1 OR f.high_id=$1) AND f.status='accepted' ORDER BY c.name_key",me,online).await?;
    let incoming=people(db,"SELECT c.id,c.display_name,c.job,c.gender,c.level FROM friendships f JOIN characters c ON c.id=f.requester_id WHERE (f.low_id=$1 OR f.high_id=$1) AND f.requester_id<>$1 AND f.status='pending' ORDER BY f.updated_at,c.id",me,online).await?;
    let outgoing=people(db,"SELECT c.id,c.display_name,c.job,c.gender,c.level FROM friendships f JOIN characters c ON c.id=CASE WHEN f.low_id=$1 THEN f.high_id ELSE f.low_id END WHERE f.requester_id=$1 AND f.status='pending' ORDER BY f.updated_at,c.id",me,online).await?;
    let guild = if let Some((id, role)) = member(db, me).await? {
        let row = sqlx::query("SELECT name,announcement FROM guilds WHERE id=$1")
            .bind(id)
            .fetch_one(&mut *db)
            .await
            .map_err(database)?;
        let mut members=people(db,"SELECT c.id,c.display_name,c.job,c.gender,c.level FROM guild_members m JOIN characters c ON c.id=m.character_id WHERE m.guild_id=$1 ORDER BY m.role='leader' DESC,m.joined_at,c.id",id,online).await?;
        let leader: Uuid = sqlx::query_scalar(
            "SELECT character_id FROM guild_members WHERE guild_id=$1 AND role='leader'",
        )
        .bind(id)
        .fetch_one(&mut *db)
        .await
        .map_err(database)?;
        for m in &mut members {
            m["role"] = json!(if m["id"] == json!(leader) {
                "leader"
            } else {
                "member"
            });
        }
        let applications = if role == "leader" {
            people(db,"SELECT c.id,c.display_name,c.job,c.gender,c.level FROM guild_applications a JOIN characters c ON c.id=a.character_id WHERE a.guild_id=$1 ORDER BY a.created_at,c.id",id,online).await?
        } else {
            vec![]
        };
        json!({"id":id,"name":row.get::<String,_>("name"),"announcement":row.get::<String,_>("announcement"),"role":role,"members":members,"applications":applications})
    } else {
        Value::Null
    };
    // Bounded directory, with own pending applications first. Exact name search is
    // handled separately so guilds beyond the first page remain discoverable.
    let rows=sqlx::query("SELECT g.id,g.name,g.announcement,(SELECT count(*) FROM guild_members m WHERE m.guild_id=g.id) AS members,EXISTS(SELECT 1 FROM guild_applications a WHERE a.guild_id=g.id AND a.character_id=$1) AS applied FROM guilds g WHERE $2='' OR g.name_key=lower($2) COLLATE \"C\" ORDER BY applied DESC,g.created_at DESC,g.id LIMIT 100")
        .bind(me).bind(search).fetch_all(&mut *db).await.map_err(database)?;
    let guilds:Vec<Value>=rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"name":r.get::<String,_>("name"),"announcement":r.get::<String,_>("announcement"),"members":r.get::<i64,_>("members"),"applied":r.get::<bool,_>("applied")})).collect();
    Ok(
        json!({"friends":friends,"incoming":incoming,"outgoing":outgoing,"guild":guild,"guilds":guilds}),
    )
}

async fn public_profile(
    db: &mut PgConnection,
    id: Uuid,
    online: &HashSet<Uuid>,
) -> Result<Value, AuthError> {
    // Allowlist only: never serialize Character or an account/session/inventory row.
    let row=sqlx::query("SELECT c.id,c.display_name,c.job,c.gender,c.school,c.level,c.hp,c.mp,c.balance_revision,c.loot_state,c.allocated_attributes,COALESCE((SELECT jsonb_object_agg(i.definition_id,true) FROM inventory_items i WHERE i.character_id=c.id AND i.equipped),'{}'::jsonb) AS gear,(SELECT jsonb_build_object('id',g.id,'name',g.name,'role',m.role) FROM guild_members m JOIN guilds g ON g.id=m.guild_id WHERE m.character_id=c.id) AS guild FROM characters c JOIN accounts a ON a.id=c.account_id WHERE c.id=$1 AND c.deleted_at IS NULL AND NOT a.disabled")
        .bind(id).fetch_optional(db).await.map_err(database)?;
    let Some(r) = row else { return Ok(Value::Null) };
    let gear: BTreeMap<String, bool> = r.get::<DbJson<BTreeMap<String, bool>>, _>("gear").0;
    let allocated: [i32; 5] = r
        .get::<Vec<i32>, _>("allocated_attributes")
        .try_into()
        .map_err(|_| invalid())?;
    let job: i16 = r.get("job");
    let level: i32 = r.get("level");
    let mut stats = crate::attributes::profile(job, level, false, allocated)["combat"].clone();
    let (attack, defense) = crate::shop::bonus(&gear);
    for k in ["physical_attack", "magic_attack"] {
        stats[k] = json!(stats[k].as_i64().unwrap() + i64::from(attack));
    }
    for k in ["physical_defense", "magic_defense"] {
        stats[k] = json!(stats[k].as_i64().unwrap() + i64::from(defense));
    }
    let loot:crate::loot::State=serde_json::from_value(r.get::<DbJson<Value>,_>("loot_state").0).map_err(|_|invalid())?;
    if !loot.valid(job,r.get("gender")){return Err(invalid());}
    if r.get::<i16,_>("balance_revision")==1{
        let mut s=crate::attributes::balanced_stats(job,level,false,allocated);
        crate::attributes::gear_bonus(&mut s,attack,defense);loot.apply_stats(&mut s,job);
        stats=crate::attributes::profile_for(s,job,level,allocated)["combat"].clone();
    }
    let mut equipped: BTreeMap<String,Option<String>> = crate::shop::SLOTS
        .into_iter()
        .map(|s| (s.into(), crate::shop::equipped(&gear, s).map(str::to_owned)))
        .collect();
    for i in loot.items.iter().filter(|i|i.equipped&&!i.legacy){equipped.insert(i.slot().into(),Some(i.template.clone()));}
    let vitals=json!({"hp":r.get::<i32,_>("hp").clamp(0,stats["hp"].as_i64().unwrap() as i32),"mp":r.get::<i32,_>("mp").clamp(0,stats["mp"].as_i64().unwrap() as i32)});
    Ok(
        json!({"id":id,"display_name":r.get::<String,_>("display_name"),"job":job,"gender":r.get::<i16,_>("gender"),"school":r.get::<i16,_>("school"),"level":level,"online":online.contains(&id),"appearance":loot.look(crate::shop::appearance(&gear)),"combat":stats,"vitals":vitals,"equipment":equipped,"guild":r.get::<Option<DbJson<Value>>,_>("guild").map(|v|v.0)}),
    )
}
