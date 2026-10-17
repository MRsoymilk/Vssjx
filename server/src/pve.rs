//! Durable character-scoped commands. State, inventory, battle and receipt commit together.
use crate::{
    auth::{AuthError, AuthService},
    characters::{CHARACTER_COLUMNS, Character},
    population,
    pve_rules::{self, Action, Battle, Command},
};
use axum::http::StatusCode;
use rand::Rng;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, Postgres, Row, Transaction, types::Json};
use std::{
    collections::BTreeMap,
    time::{SystemTime, UNIX_EPOCH},
};
use uuid::Uuid;

pub const MONSTER_RESPAWN_MS: i64 = 30_000;
fn unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

pub struct Context {
    pub character: Uuid,
    pub session: Uuid,
    pub owner: i64,
    pub cell: [i32; 2],
    pub target_cell: Option<[i32; 2]>,
    pub moving: bool,
    pub map_id: String,
    pub position_revision: u64,
}
#[derive(Clone)]
struct Loaded {
    character: Character,
    defeated: i32,
    respawns: BTreeMap<String, i64>,
    battle: Option<Battle>,
    potions: i32,
    equipped: bool,
    weapon_owned: bool,
    allocated: [i32; 5],
    gear: BTreeMap<String,bool>,
    quantities: BTreeMap<String,i32>,
}
fn database(error: sqlx::Error) -> AuthError {
    crate::observability::database_error(&error, "online_pve");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn unavailable() -> AuthError {
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "PVE_STATE_UNAVAILABLE")
}

async fn load(tx: &mut Transaction<'_, Postgres>, context: &Context) -> Result<Loaded, AuthError> {
    let account: Option<Uuid> = sqlx::query_scalar("SELECT s.account_id FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.id=$1 AND NOT a.disabled AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp() FOR SHARE OF s,a")
        .bind(context.session).fetch_optional(&mut **tx).await.map_err(database)?;
    let account = account.ok_or(AuthError(StatusCode::UNAUTHORIZED, "SESSION_REVOKED"))?;
    let row=sqlx::query(&format!("SELECT {CHARACTER_COLUMNS},defeated_mask,monster_respawns,active_battle_id,owner_epoch,allocated_attributes FROM characters WHERE id=$1 AND account_id=$2 FOR UPDATE"))
        .bind(context.character).bind(account).fetch_optional(&mut **tx).await.map_err(database)?
        .ok_or(AuthError(StatusCode::FORBIDDEN,"FORBIDDEN"))?;
    if row.get::<i64, _>("owner_epoch") != context.owner {
        return Err(AuthError(StatusCode::CONFLICT, "SESSION_REPLACED"));
    }
    let character = Character::from_row(&row).map_err(database)?;
    let Json(respawns) = row.get::<Json<Value>, _>("monster_respawns");
    let respawns: BTreeMap<String, i64> =
        serde_json::from_value(respawns).map_err(|_| unavailable())?;
    if respawns.len() > 6
        || respawns.iter().any(|(id, deadline)| {
            pve_rules::mask(id).is_none_or(|mask| row.get::<i32, _>("defeated_mask") & mask == 0)
                || !(0..=253_402_300_799_999).contains(deadline)
        })
    {
        return Err(unavailable());
    }
    let active: Option<Uuid> = row.get("active_battle_id");
    let battle = if let Some(id) = active {
        let row=sqlx::query("SELECT state,rules_version FROM pve_battles WHERE id=$1 AND character_id=$2 AND active FOR UPDATE")
            .bind(id).bind(context.character).fetch_optional(&mut **tx).await.map_err(database)?.ok_or_else(unavailable)?;
        if row.get::<String, _>("rules_version") != pve_rules::RULES {
            return Err(unavailable());
        }
        let Json(value) = row.get::<Json<Value>, _>("state");
        Some(serde_json::from_value::<Battle>(value).map_err(|_| unavailable())?)
    } else {
        None
    };
    let potions:i32=sqlx::query_scalar("SELECT COALESCE(SUM(quantity),0)::int FROM inventory_items WHERE character_id=$1 AND definition_id='potion'")
        .bind(context.character).fetch_one(&mut **tx).await.map_err(database)?;
    let equipped:Option<bool>=sqlx::query_scalar("SELECT equipped FROM inventory_items WHERE character_id=$1 AND definition_id='sword'")
        .bind(context.character).fetch_optional(&mut **tx).await.map_err(database)?;
    let rows=sqlx::query("SELECT definition_id,equipped,quantity FROM inventory_items WHERE character_id=$1 AND definition_id<>'potion'").bind(context.character).fetch_all(&mut **tx).await.map_err(database)?;
    let quantities=rows.iter().map(|r|(r.get("definition_id"),r.get("quantity"))).collect();
    let gear = rows.into_iter().map(|r|(r.get("definition_id"),r.get("equipped"))).collect();
    Ok(Loaded {
        gear,
        quantities,
        character,
        defeated: row.get("defeated_mask"),
        respawns,
        battle,
        potions,
        equipped: equipped.unwrap_or(false),
        weapon_owned: equipped.is_some(),
        allocated: row
            .get::<Vec<i32>, _>("allocated_attributes")
            .try_into()
            .map_err(|_| unavailable())?,
    })
}
impl Loaded {
    fn stats(&self) -> pve_rules::Stats {
        let mut stats = crate::attributes::stats(
            self.character.job,
            self.character.level,
            self.equipped,
            self.allocated,
        );
        let (attack,defense) = crate::shop::bonus(&self.gear);
        stats.attack += attack - if self.equipped {5} else {0};
        stats.defense += defense;
        stats
    }
    fn state(&self) -> Value {
        let defeated: Vec<_> = population::definitions()
            .into_iter()
            .chain(population::definitions_for("ancient_ruins"))
            .filter(|d| pve_rules::mask(&d.id).is_some_and(|mask| self.defeated & mask != 0))
            .map(|d| d.id)
            .collect();
        let mut profile = crate::attributes::profile(self.character.job,self.character.level,self.equipped,self.allocated);
        let (attack,_) = crate::shop::bonus(&self.gear);
        for key in ["physical_attack","magic_attack"] { profile["combat"][key] = json!(profile["combat"][key].as_i64().unwrap() + i64::from(attack - if self.equipped {5} else {0})); }
        for key in ["physical_defense","magic_defense"] { profile["combat"][key] = json!(self.stats().defense); }
        json!({"rules_version":pve_rules::RULES,"character":self.character,"potions":self.potions,
            "equipment":{"version":"equipment-v1","weapon_owned":self.weapon_owned,"weapon":if self.equipped {Some("sword")} else {None}},
            "stats":self.stats(),
            "attributes":profile,"shop":crate::shop::view(&self.gear,&self.quantities,self.potions),
            "skills":crate::skills::view(self.character.job,self.character.school,self.character.level),
            "server_time_ms":unix_ms(),
            "progress":{"kills":(self.defeated&7).count_ones(),"defeated":defeated,"respawns":self.respawns},"battle":self.battle.as_ref().map(Battle::view)})
    }
    fn rewards(&mut self, gold: i32, xp: i32) -> Result<(), &'static str> {
        self.character.gold = self
            .character
            .gold
            .checked_add(gold)
            .ok_or("REWARD_LIMIT")?;
        self.character.xp = self.character.xp.checked_add(xp).ok_or("REWARD_LIMIT")?;
        let mut leveled = false;
        while self.character.level < 60 && self.character.xp >= self.character.level * 40 {
            self.character.xp -= self.character.level * 40;
            self.character.level += 1;
            leveled = true;
        }
        if leveled {
            self.restore();
        }
        Ok(())
    }
    fn restore(&mut self) {
        let stats = self.stats();
        self.character.hp = stats.hp;
        self.character.mp = stats.mp;
    }
    fn apply(&mut self, command: &Command, context: &Context) -> Result<Vec<String>, &'static str> {
        if context.map_id != self.character.map_id {
            return Err("MAP_CHANGED");
        }
        if context.moving {
            return Err("PLAYER_MOVING");
        }
        if matches!(command.action,Action::Buy|Action::Equip|Action::Unequip|Action::Use|Action::Discard) {
            if self.battle.is_some(){return Err("BATTLE_ACTIVE");}
            if command.battle_id.is_some()||command.attributes.is_some(){return Err("INVALID_EQUIPMENT");}
            let id=command.target.as_deref().ok_or("INVALID_EQUIPMENT")?;
            let item=crate::shop::item(id).ok_or("INVALID_EQUIPMENT")?;
            let count=command.quantity.unwrap_or(1);
            if !(1..=99).contains(&count)||(item.equipment()&&count!=1)||(!matches!(command.action,Action::Buy|Action::Discard)&&count!=1){return Err("INVALID_QUANTITY");}
            if command.expected_revision.as_deref()!=Some(&self.character.state_revision){return Err("STALE_EQUIPMENT");}
            let current=if id=="potion"{self.potions}else{*self.quantities.get(id).unwrap_or(&0)};
            let bag_count=self.gear.values().filter(|on|!**on).count()+usize::from(self.potions>0);
            if command.action==Action::Buy {
                if item.equipment()&&current>0{return Err("ITEM_ALREADY_OWNED");}
                if current+count>99||(current==0&&bag_count>=60){return Err("BAG_FULL");}
                let price=item.price.checked_mul(count).ok_or("INVALID_QUANTITY")?;
                if self.character.gold<price{return Err("GOLD_INSUFFICIENT");}
                self.character.gold-=price;
                if id=="potion"{self.potions+=count;}else{self.quantities.insert(id.into(),current+count);self.gear.entry(id.into()).or_insert(false);}
                self.weapon_owned=self.gear.contains_key("sword");
                return Ok(vec![format!("购得{}×{}，花费{}铜钱。",item.name,count,price)]);
            }
            if current<count{return Err("WEAPON_NOT_OWNED");}
            if matches!(command.action,Action::Use|Action::Discard) {
                if command.action==Action::Use {
                    if item.slot!="consumable"{return Err("ITEM_NOT_USABLE");}
                    let limits=self.stats();
                    if (item.restore_hp==0||self.character.hp>=limits.hp)&&(item.restore_mp==0||self.character.mp>=limits.mp){return Err("HP_FULL");}
                    self.character.hp=(self.character.hp+item.restore_hp).min(limits.hp);
                    self.character.mp=(self.character.mp+item.restore_mp).min(limits.mp);
                }
                if id=="potion"{self.potions-=count;}else if current==count{self.quantities.remove(id);self.gear.remove(id);}else{self.quantities.insert(id.into(),current-count);}
                self.equipped=self.gear.get("sword")==Some(&true);self.weapon_owned=self.gear.contains_key("sword");
                return Ok(vec![format!("已{}{}×{}。",if command.action==Action::Use{"使用"}else{"丢弃"},item.name,count)]);
            }
            if !item.equipment(){return Err("INVALID_EQUIPMENT");}
            if command.action==Action::Equip&&item.job>=0&&item.job!=self.character.job{return Err("WRONG_JOB");}
            let on=command.action==Action::Equip;
            if self.gear.get(id)==Some(&on){return Err("EQUIPMENT_UNCHANGED");}
            if !on&&bag_count>=60{return Err("BAG_FULL");}
            if on{for (other,value) in &mut self.gear{if crate::shop::item(other).is_some_and(|i|i.slot==item.slot){*value=false;}}}
            self.gear.insert(id.into(),on);self.equipped=self.gear.get("sword")==Some(&true);
            return Ok(vec![format!("已{}{}。",if on{"装备"}else{"卸下"},item.name)]);
        }
        if command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
        if command.action == Action::Transfer {
            if self.battle.is_some() { return Err("BATTLE_ACTIVE"); }
            if command.battle_id.is_some() || command.expected_revision.is_some() || command.attributes.is_some() {
                return Err("INVALID_PVE_COMMAND");
            }
            let map = crate::world_map::WorldMap::load(&context.map_id).ok_or("INVALID_MAP")?;
            let (gate, cell, destination, spawn) = map.portal();
            if command.target.as_deref() != Some(gate) { return Err("INVALID_PORTAL"); }
            if (cell[0] - context.cell[0]).abs() + (cell[1] - context.cell[1]).abs() > 2 { return Err("PORTAL_TOO_FAR"); }
            if destination == "ancient_ruins" && self.character.quest_stage < 3 { return Err("PORTAL_LOCKED"); }
            self.character.map_id = destination.to_owned();
            self.character.cell_x = spawn[0];
            self.character.cell_y = spawn[1];
            return Ok(vec![if destination == "ancient_ruins" { "已进入古剑遗迹。" } else { "已返回青云山道。" }.into()]);
        }
        if command.action == Action::Allocate {
            if self.battle.is_some() {
                return Err("BATTLE_ACTIVE");
            }
            if command.target.is_some() || command.battle_id.is_some() {
                return Err("INVALID_PVE_COMMAND");
            }
            if command.expected_revision.as_deref() != Some(&self.character.state_revision) {
                return Err("STALE_ATTRIBUTES");
            }
            let points = command.attributes.ok_or("INVALID_ATTRIBUTES")?;
            if points.iter().any(|v| !(0..=300).contains(v)) {
                return Err("INVALID_ATTRIBUTES");
            }
            if points
                .iter()
                .zip(self.allocated)
                .any(|(new, old)| *new < old)
            {
                return Err("ATTRIBUTE_RESPEC_FORBIDDEN");
            }
            if crate::attributes::available(self.character.level, points) < 0 {
                return Err("ATTRIBUTE_POINTS_EXCEEDED");
            }
            if points == self.allocated {
                return Err("NO_ATTRIBUTE_CHANGE");
            }
            let old = self.stats();
            self.allocated = points;
            let new = self.stats();
            self.character.hp += new.hp - old.hp;
            self.character.mp += new.mp - old.mp;
            return Ok(vec![format!(
                "属性已保存，剩余{}点。",
                crate::attributes::available(self.character.level, self.allocated)
            )]);
        }
        if command.attributes.is_some() {
            return Err("INVALID_PVE_COMMAND");
        }
        match command.action {
            Action::Accept | Action::Claim | Action::Restore | Action::Challenge => {
                if self.battle.is_some() {
                    return Err("BATTLE_ACTIVE");
                }
                if command.battle_id.is_some() || command.expected_revision.is_some() {
                    return Err("INVALID_PVE_COMMAND");
                }
                let target = context.target_cell.ok_or("INVALID_RESIDENT")?;
                if (target[0] - context.cell[0]).abs() + (target[1] - context.cell[1]).abs() > 2 {
                    return Err("RESIDENT_TOO_FAR");
                }
                if command.action == Action::Challenge {
                    let definition = population::definitions_for(&context.map_id)
                        .into_iter()
                        .find(|d| Some(&d.id) == command.target.as_ref() && d.kind != "npc")
                        .ok_or("INVALID_RESIDENT")?;
                    if self
                        .respawns
                        .get(&definition.id)
                        .is_some_and(|deadline| *deadline > unix_ms())
                    {
                        return Err("MONSTER_RESPAWNING");
                    }
                    if self.character.quest_stage == 0 {
                        return Err("QUEST_REQUIRED");
                    }
                    let name = definition.name.clone();
                    self.battle = Some(Battle::new(
                        definition,
                        self.character.hp,
                        self.character.mp,
                        self.potions,
                    ));
                    return Ok(vec![format!("与{name}的遭遇战开始。")]);
                }
                if command.target.as_deref() != Some("qingwei") {
                    return Err("INVALID_RESIDENT");
                }
                match command.action {
                    Action::Accept => {
                        if self.character.quest_stage != 0 {
                            return Err("QUEST_ALREADY_ACCEPTED");
                        }
                        self.character.quest_stage = 1;
                        self.restore();
                        Ok(vec![
                            "已领受山林试炼：击败三只不同的山狼，再回来领取奖励。".into(),
                        ])
                    }
                    Action::Claim => {
                        if self.character.quest_stage != 2 {
                            return Err("QUEST_NOT_READY");
                        }
                        self.character.quest_stage = 3;
                        self.rewards(60, 35)?;
                        self.restore();
                        Ok(vec![
                            "山林试炼完成！获得60铜钱、35修为，恢复全部元气。".into(),
                        ])
                    }
                    Action::Restore => {
                        self.restore();
                        Ok(vec!["清微道人为你恢复了生命与灵力。".into()])
                    }
                    _ => unreachable!(),
                }
            }
            action => {
                if command.target.is_some() && action!=Action::Skill {
                    return Err("INVALID_PVE_COMMAND");
                }
                let stats = self.stats();
                let battle = self.battle.as_mut().ok_or("NO_ACTIVE_BATTLE")?;
                if command.battle_id != Some(battle.id)
                    || command
                        .expected_revision
                        .as_ref()
                        .is_none_or(|revision| revision != &battle.revision.to_string())
                {
                    return Err("STALE_BATTLE");
                }
                let mut rng = rand::thread_rng();
                let mut lines = battle.turn_selected(
                    action,
                    self.character.job,
                    self.character.school,
                    self.character.level,
                    stats,
                    rng.gen_range(-2..=2),
                    rng.gen_range(-2..=2),
                    command.target.as_deref(),
                    rng.gen_range(0..100),
                )?;
                self.character.hp = battle.hp.max(1);
                self.character.mp = battle.mp;
                self.potions = battle.potions;
                if battle.outcome == "victory" {
                    let gold = battle.enemy.gold;
                    let xp = battle.enemy.xp;
                    self.defeated |= pve_rules::mask(&battle.enemy.id).ok_or("INVALID_RESIDENT")?;
                    self.respawns
                        .insert(battle.enemy.id.clone(), unix_ms() + MONSTER_RESPAWN_MS);
                    if self.character.quest_stage == 1 && self.defeated & 7 == 7 {
                        self.character.quest_stage = 2;
                        lines.push("三只山狼已清除，请返回清微道人处领取奖励。".into());
                    }
                    if battle.enemy.id == "boss" && self.character.quest_stage == 3 {
                        self.character.quest_stage = 4;
                        lines.push("赤焰妖王已被击败，古剑遗迹的妖气消散了。".into());
                    }
                    self.rewards(gold, xp)?;
                    lines.push(format!("获得{gold}铜钱、{xp}修为。"));
                } else if battle.outcome == "defeat" {
                    self.restore();
                }
                Ok(lines)
            }
        }
    }
}
pub async fn snapshot(auth: &AuthService, context: &Context) -> Result<Value, AuthError> {
    let mut tx = auth.pool().begin().await.map_err(database)?;
    let loaded = load(&mut tx, context).await?;
    let value = json!({"type":"pve.state","state":loaded.state()});
    tx.commit().await.map_err(database)?;
    Ok(value)
}
pub async fn execute(
    auth: &AuthService,
    context: &Context,
    command: &Command,
) -> Result<Value, AuthError> {
    if command.operation_id.get_version_num() != 4
        || command.target.as_ref().is_some_and(|id| id.len() > 32)
    {
        return Err(AuthError(StatusCode::BAD_REQUEST, "INVALID_PVE_COMMAND"));
    }
    let digest =
        Sha256::digest(serde_json::to_vec(&(pve_rules::RULES, command)).expect("PVE request"))
            .to_vec();
    let mut tx = auth.pool().begin().await.map_err(database)?;
    let account: Uuid = sqlx::query_scalar("SELECT s.account_id FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.id=$1 AND NOT a.disabled AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp()")
        .bind(context.session).fetch_optional(&mut *tx).await.map_err(database)?.ok_or(AuthError(StatusCode::UNAUTHORIZED,"SESSION_REVOKED"))?;
    // Before locking the character, serialize this account's budget across characters,
    // connections and processes. A fixed minute is an abuse budget, not a turn timer.
    let admitted: bool = sqlx::query_scalar("INSERT INTO gameplay_budgets(account_id,window_start,requests) VALUES($1,clock_timestamp(),1) ON CONFLICT(account_id) DO UPDATE SET requests=CASE WHEN gameplay_budgets.window_start<=clock_timestamp()-interval '60 seconds' THEN 1 ELSE LEAST(gameplay_budgets.requests+1,181) END, window_start=CASE WHEN gameplay_budgets.window_start<=clock_timestamp()-interval '60 seconds' THEN clock_timestamp() ELSE gameplay_budgets.window_start END RETURNING requests<=180")
        .bind(account).fetch_one(&mut *tx).await.map_err(database)?;
    let action = format!("pve.{}",serde_json::to_value(command.action).expect("typed action").as_str().expect("action string"));
    let target = command.target.as_deref().map(|v| if crate::shop::item(v).is_some() || crate::skills::item(v).is_some() || ["sword","qingwei","wolf_a","wolf_b","wolf_c","spirit","guardian","boss","ruins","trail_gate"].contains(&v) { v } else { "[invalid]" });
    if !admitted {
        // One bounded audit event per exhausted window, not one per flood packet.
        let logged = sqlx::query("SELECT 1 FROM security_audit WHERE account_id=$1 AND code='GAMEPLAY_RATE_LIMITED' AND created_at>clock_timestamp()-interval '60 seconds' LIMIT 1")
            .bind(account).fetch_optional(&mut *tx).await.map_err(database)?.is_some();
        if !logged { crate::security::append(&mut *tx, crate::security::Event {account:Some(account),character:Some(context.character),session:Some(context.session),operation:Some(command.operation_id),action:"pve.rate_limit",outcome:"rejected",code:"GAMEPLAY_RATE_LIMITED",details:json!({"limit":180,"window_seconds":60})}).await.map_err(database)?; }
        tx.commit().await.map_err(database)?;
        return Err(AuthError(StatusCode::TOO_MANY_REQUESTS,"GAMEPLAY_RATE_LIMITED"));
    }
    let mut loaded = load(&mut tx, context).await?;
    let previous=sqlx::query("SELECT request_digest,result FROM pve_operation_receipts WHERE character_id=$1 AND operation_id=$2")
        .bind(context.character).bind(command.operation_id).fetch_optional(&mut *tx).await.map_err(database)?;
    if let Some(row) = previous {
        let mut result = if row.get::<Vec<u8>, _>("request_digest") == digest {
            row.get::<Json<Value>, _>("result").0
        } else {
            json!({"type":"pve.result","operation_id":command.operation_id,"ok":false,"code":"PVE_ID_CONFLICT","lines":[],"state":loaded.state()})
        };
        result["replayed"] = json!(true);
        crate::security::append(&mut *tx, crate::security::Event{account:Some(account),character:Some(context.character),session:Some(context.session),operation:Some(command.operation_id),action:&action,outcome:if result["code"]=="PVE_ID_CONFLICT" {"rejected"} else {"replayed"},code:result["code"].as_str().unwrap_or("OK"),details:json!({"target":target,"changed":false})}).await.map_err(database)?;
        tx.commit().await.map_err(database)?;
        return Ok(result);
    }
    let previous_gear = loaded.gear.clone();
    let previous_quantities=loaded.quantities.clone();
    let original = loaded.clone();
    let before = crate::security::state_summary(&original.state());
    let applied = loaded.apply(command, context);
    if applied.is_err() {
        loaded = original;
    }
    if applied.is_ok() {
        if loaded.gear!=previous_gear||loaded.quantities!=previous_quantities {
            sqlx::query("UPDATE inventory_items SET equipped=FALSE WHERE character_id=$1 AND definition_id<>'potion'").bind(context.character).execute(&mut *tx).await.map_err(database)?;
            let ids:Vec<_>=loaded.gear.keys().cloned().collect();
            sqlx::query("DELETE FROM inventory_items WHERE character_id=$1 AND definition_id<>'potion' AND NOT(definition_id=ANY($2))").bind(context.character).bind(&ids).execute(&mut *tx).await.map_err(database)?;
            if !ids.is_empty(){
                let uuids:Vec<_>=ids.iter().map(|_|Uuid::new_v4()).collect();
                let counts:Vec<_>=ids.iter().map(|id|loaded.quantities[id]).collect();
                let flags:Vec<_>=ids.iter().map(|id|loaded.gear[id]).collect();
                sqlx::query("INSERT INTO inventory_items(id,character_id,definition_id,quantity,equipped) SELECT u,$1,d,q,e FROM unnest($2::uuid[],$3::text[],$4::int[],$5::bool[]) AS items(u,d,q,e) ON CONFLICT(character_id,definition_id) DO UPDATE SET quantity=EXCLUDED.quantity,equipped=EXCLUDED.equipped")
                    .bind(context.character).bind(uuids).bind(&ids).bind(counts).bind(flags).execute(&mut *tx).await.map_err(database)?;
            }
        }
        if loaded.character.map_id != context.map_id {
            sqlx::query("UPDATE characters SET map_id=$2,cell_x=$3,cell_y=$4,position_revision=$5 WHERE id=$1 AND owner_epoch=$6")
                .bind(context.character).bind(&loaded.character.map_id).bind(loaded.character.cell_x).bind(loaded.character.cell_y)
                .bind((context.position_revision + 1) as i64).bind(context.owner)
                .execute(&mut *tx).await.map_err(database)?;
        }
        let active = loaded
            .battle
            .as_ref()
            .filter(|b| b.outcome == "active")
            .map(|b| b.id);
        if let Some(battle) = &loaded.battle {
            sqlx::query("INSERT INTO pve_battles(id,character_id,rules_version,state,active) VALUES($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET state=EXCLUDED.state,active=EXCLUDED.active,updated_at=NOW()")
                .bind(battle.id).bind(context.character).bind(pve_rules::RULES).bind(Json(serde_json::to_value(battle).expect("durable battle"))).bind(active.is_some()).execute(&mut *tx).await.map_err(database)?;
        }
        let character_id = loaded.character.id;
        let c = &loaded.character;
        let revision:i64=sqlx::query_scalar("UPDATE characters SET level=$2,xp=$3,gold=$4,hp=$5,mp=$6,quest_stage=$7,defeated_mask=$8,active_battle_id=$9,allocated_attributes=$10,monster_respawns=$11,state_revision=state_revision+1 WHERE id=$1 RETURNING state_revision")
            .bind(c.id).bind(c.level).bind(c.xp).bind(c.gold).bind(c.hp).bind(c.mp).bind(c.quest_stage).bind(loaded.defeated).bind(active).bind(loaded.allocated.to_vec()).bind(Json(&loaded.respawns))
            .fetch_one(&mut *tx).await.map_err(database)?;
        loaded.character.state_revision = revision.to_string();
        if loaded.potions == 0 {
            sqlx::query(
                "DELETE FROM inventory_items WHERE character_id=$1 AND definition_id='potion'",
            )
            .bind(character_id)
            .execute(&mut *tx)
            .await
            .map_err(database)?;
        } else {
            sqlx::query("INSERT INTO inventory_items(id,character_id,definition_id,quantity) VALUES($3,$1,'potion',$2) ON CONFLICT(character_id,definition_id) DO UPDATE SET quantity=EXCLUDED.quantity").bind(character_id).bind(loaded.potions).bind(Uuid::new_v4()).execute(&mut *tx).await.map_err(database)?;
        }
    }
    let result = match applied {
        Ok(lines) => {
            json!({"type":"pve.result","operation_id":command.operation_id,"ok":true,"replayed":false,"lines":lines,"state":loaded.state()})
        }
        Err(code) => {
            json!({"type":"pve.result","operation_id":command.operation_id,"ok":false,"replayed":false,"code":code,"lines":[],"state":loaded.state()})
        }
    };
    sqlx::query("INSERT INTO pve_operation_receipts(character_id,operation_id,request_digest,result) VALUES($1,$2,$3,$4)")
        .bind(context.character).bind(command.operation_id).bind(digest).bind(Json(result.clone())).execute(&mut *tx).await.map_err(database)?;
    crate::security::append(&mut *tx, crate::security::Event{account:Some(account),character:Some(context.character),session:Some(context.session),operation:Some(command.operation_id),action:&action,outcome:if result["ok"]==true {"accepted"} else {"rejected"},code:result["code"].as_str().unwrap_or("OK"),details:json!({"target":target,"before":before,"after":crate::security::state_summary(&loaded.state())})}).await.map_err(database)?;
    tx.commit().await.map_err(database)?;
    Ok(result)
}
