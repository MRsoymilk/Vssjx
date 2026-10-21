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
    pub duel_active: bool,
}
#[derive(Clone)]
struct Loaded {
    hunt_pressure: crate::monster_combat::HuntPressure,
    ai: crate::ai_world::Progress,
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
    loot:crate::loot::State,
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
    load_character(tx,context.character,account,Some(context.owner)).await
}
async fn load_character(tx:&mut Transaction<'_,Postgres>,character_id:Uuid,account:Uuid,owner:Option<i64>)->Result<Loaded,AuthError>{
    let row=sqlx::query(&format!("SELECT {CHARACTER_COLUMNS},loot_state,ai_progress,defeated_mask,monster_respawns,active_battle_id,owner_epoch,allocated_attributes,hunt_pressure FROM characters WHERE id=$1 AND account_id=$2 FOR UPDATE"))
        .bind(character_id).bind(account).fetch_optional(&mut **tx).await.map_err(database)?
        .ok_or(AuthError(StatusCode::FORBIDDEN,"FORBIDDEN"))?;
    if owner.is_some_and(|owner|row.get::<i64, _>("owner_epoch") != owner) {
        return Err(AuthError(StatusCode::CONFLICT, "SESSION_REPLACED"));
    }
    let character = Character::from_row(&row).map_err(database)?;
    if character.corpse.as_ref().is_some_and(|corpse|!corpse.0.valid()||corpse.0.map_id!=character.map_id||character.hp!=0) {
        return Err(unavailable());
    }
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
            .bind(id).bind(character_id).fetch_optional(&mut **tx).await.map_err(database)?.ok_or_else(unavailable)?;
        if row.get::<String, _>("rules_version") != pve_rules::RULES {
            return Err(unavailable());
        }
        let Json(value) = row.get::<Json<Value>, _>("state");
        Some(serde_json::from_value::<Battle>(value).map_err(|_| unavailable())?)
    } else {
        None
    };
    let potions:i32=sqlx::query_scalar("SELECT COALESCE(SUM(quantity),0)::int FROM inventory_items WHERE character_id=$1 AND definition_id='potion'")
        .bind(character_id).fetch_one(&mut **tx).await.map_err(database)?;
    let equipped:Option<bool>=sqlx::query_scalar("SELECT equipped FROM inventory_items WHERE character_id=$1 AND definition_id='sword'")
        .bind(character_id).fetch_optional(&mut **tx).await.map_err(database)?;
    let rows=sqlx::query("SELECT definition_id,equipped,quantity FROM inventory_items WHERE character_id=$1 AND definition_id<>'potion'").bind(character_id).fetch_all(&mut **tx).await.map_err(database)?;
    let quantities=rows.iter().map(|r|(r.get("definition_id"),r.get("quantity"))).collect();
    let gear = rows.into_iter().map(|r|(r.get("definition_id"),r.get("equipped"))).collect();
    let ai:crate::ai_world::Progress=serde_json::from_value(row.get::<Json<Value>,_>("ai_progress").0).map_err(|_|unavailable())?;
    if !ai.valid(){return Err(unavailable());}
    let mut loaded = Loaded {
        hunt_pressure:serde_json::from_value(row.get::<Json<Value>,_>("hunt_pressure").0).map_err(|_|unavailable())?,
        loot:serde_json::from_value(row.get::<Json<Value>,_>("loot_state").0).map_err(|_|unavailable())?,
        ai,
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
    };
    if !loaded.hunt_pressure.valid(){return Err(unavailable());}
    if !loaded.loot.valid(loaded.character.job,loaded.character.gender){return Err(unavailable());}
    let previous_loot=loaded.loot.clone();
    loaded.loot.sync_legacy(&loaded.gear,loaded.character.job,loaded.character.gender);
    if !loaded.loot.valid(loaded.character.job,loaded.character.gender)||loaded.loot.items.iter().any(|i|i.equipped&&i.level>loaded.character.level){return Err(unavailable());}
    if previous_loot!=loaded.loot{
        let revision:i64=sqlx::query_scalar("UPDATE characters SET loot_state=$2,state_revision=state_revision+1 WHERE id=$1 RETURNING state_revision").bind(character_id).bind(Json(&loaded.loot)).fetch_one(&mut **tx).await.map_err(database)?;
        loaded.character.state_revision=revision.to_string();
    }
    if loaded.character.balance_revision==0&&loaded.battle.is_none(){
        let team_active:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members m JOIN team_battles b ON b.team_id=m.team_id AND b.active WHERE m.character_id=$1)").bind(character_id).fetch_one(&mut **tx).await.map_err(database)?;
        if !team_active{
            let previous=loaded.stats();loaded.character.balance_revision=1;
            let next=loaded.stats();
            if loaded.character.corpse.is_none(){loaded.character.hp=((i64::from(loaded.character.hp)*i64::from(next.hp))/i64::from(previous.hp)).clamp(1,i64::from(next.hp)) as i32;}
            loaded.character.mp=((i64::from(loaded.character.mp)*i64::from(next.mp))/i64::from(previous.mp)).clamp(0,i64::from(next.mp)) as i32;
            let rev:i64=sqlx::query_scalar("UPDATE characters SET balance_revision=1,hp=$2,mp=$3,state_revision=state_revision+1 WHERE id=$1 RETURNING state_revision").bind(character_id).bind(loaded.character.hp).bind(loaded.character.mp).fetch_one(&mut **tx).await.map_err(database)?;
            loaded.character.state_revision=rev.to_string();
        }
    }
    // Formula updates retain allocations and never refill resources on login.
    let maxima = loaded.stats();
    loaded.character.hp = loaded.character.hp.min(maxima.hp);
    loaded.character.mp = loaded.character.mp.min(maxima.mp);
    if let Some(b) = loaded.battle.as_mut() {
        b.hp = b.hp.min(maxima.hp);
        b.mp = b.mp.min(maxima.mp);
    }
    Ok(loaded)
}
impl Loaded {
    fn stats(&self) -> pve_rules::Stats {
        if let Some(stats)=self.battle.as_ref().filter(|b|b.outcome=="active").and_then(|b|b.frozen_stats){return stats;}
        let factory=if self.character.balance_revision==1{crate::attributes::balanced_stats}else{crate::attributes::stats};
        let mut stats = factory(
            self.character.job,
            self.character.level,
            self.equipped,
            self.allocated,
        );
        let (attack,defense) = crate::shop::bonus(&self.gear);
        crate::attributes::gear_bonus(&mut stats,attack-if self.equipped{5}else{0},defense);
        self.loot.apply_stats(&mut stats,self.character.job);
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
        if self.stats().balance.is_some(){profile=crate::attributes::profile_for(self.stats(),self.character.job,self.character.level,self.allocated);}
        json!({"rules_version":pve_rules::RULES,"character":self.character,"potions":self.potions,
            "equipment":{"version":"equipment-v1","weapon_owned":self.weapon_owned,"weapon":if self.equipped {Some("sword")} else {None}},
            "stats":self.stats(),"hunt_pressure":self.hunt_pressure,
            "loot":self.loot.view(crate::shop::appearance(&self.gear)),
            "attributes":profile,"shop":crate::shop::view(&self.gear,&self.quantities,self.potions),
            "skills":crate::skills::view(self.character.job,self.character.school,self.character.level),
            "ai_world":self.ai.view(&self.character.map_id),
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
        if self.character.corpse.is_some() { return; }
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
        if command.encounter_version.is_some() && (!matches!(command.encounter_version,Some(1|2))||command.action!=Action::Challenge){return Err("INVALID_PVE_COMMAND");}
        if command.enemy_slot.is_some() && (!matches!(command.action,Action::Attack|Action::Skill) || self.battle.as_ref().is_none_or(|b|b.formation.is_none())){return Err("INVALID_BATTLE_TARGET");}
        if let Some(corpse)=self.character.corpse.as_ref() {
            if command.action!=Action::Revive { return Err("SOUL_STATE"); }
            if command.battle_id.is_some()||command.attributes.is_some()||command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
            if command.expected_revision.as_deref()!=Some(&self.character.state_revision){return Err("STALE_CORPSE");}
            if command.target.as_deref()!=Some(corpse.0.id.to_string().as_str()){return Err("CORPSE_NOT_FOUND");}
            if !corpse.0.can_recover(&context.map_id,context.cell){return Err("CORPSE_TOO_FAR");}
            self.character.corpse=None;
            self.restore();
            return Ok(vec!["你寻回了自己的尸体，灵魂与肉身重新合一，气血与灵力恢复。".into()]);
        }
        if command.action==Action::Revive {return Err("NO_CORPSE");}
        if matches!(command.action,Action::GearEquip|Action::GearUnequip|Action::GearClaim|Action::GearFocus|Action::GearSalvage|Action::GearReroll|Action::GearUpgrade){
            if self.battle.is_some(){return Err("BATTLE_ACTIVE");}
            if command.expected_revision.as_deref()!=Some(&self.character.state_revision){return Err("STALE_EQUIPMENT");}
            if (command.quantity.is_some()&&command.action!=Action::GearReroll)||command.battle_id.is_some()||command.attributes.is_some()||command.enemy_slot.is_some()||command.encounter_version.is_some(){return Err("INVALID_LOOT_COMMAND");}
            if command.action==Action::GearFocus{
                let target=command.target.as_deref().ok_or("INVALID_LOOT_COMMAND")?;
                if target!="any"&&!crate::shop::SLOTS.contains(&target){return Err("INVALID_LOOT_COMMAND");}
                self.loot.focus=if target=="any"{String::new()}else{target.into()};return Ok(vec!["掉落定向已保存；保底流派装备可能跨部位。".into()]);
            }
            let id=Uuid::parse_str(command.target.as_deref().ok_or("INVALID_LOOT_COMMAND")?).map_err(|_|"INVALID_LOOT_COMMAND")?;
            if matches!(command.action,Action::GearSalvage|Action::GearReroll|Action::GearUpgrade){
                let action=match command.action{Action::GearSalvage=>"gear_salvage",Action::GearReroll=>"gear_reroll",_=>"gear_upgrade"};
                let index=if command.action==Action::GearReroll{let n=command.quantity.ok_or("INVALID_AFFIX_INDEX")?;if !(1..=4).contains(&n){return Err("INVALID_AFFIX_INDEX");}Some((n-1) as usize)}else{None};
                crate::progression::craft(&mut self.loot,id,action,index,&mut self.character.gold,rand::random())?;
                let stats=self.stats();self.character.hp=self.character.hp.min(stats.hp);self.character.mp=self.character.mp.min(stats.mp);
                return Ok(vec!["装备养成与材料消耗已保存。".into()]);
            }
            let action=match command.action{Action::GearEquip=>"gear_equip",Action::GearUnequip=>"gear_unequip",_=>"gear_claim"};
            let bag=self.bag_count();
            self.loot.apply(action,id,&mut self.gear,self.character.level,bag)?;
            self.equipped=self.gear.get("sword")==Some(&true);
            let stats=self.stats();self.character.hp=self.character.hp.min(stats.hp);self.character.mp=self.character.mp.min(stats.mp);
            return Ok(vec!["装备实例已保存。".into()]);
        }
        if command.action==Action::Respec {
            if self.battle.is_some(){return Err("BATTLE_ACTIVE");}
            if !self.character.balance_respec_available{return Err("RESPEC_USED");}
            if command.expected_revision.as_deref()!=Some(&self.character.state_revision){return Err("STALE_ATTRIBUTES");}
            if command.target.is_some()||command.battle_id.is_some()||command.attributes.is_some()||command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
            let before=self.stats();self.allocated=[0;5];let next=self.stats();
            self.character.hp=(i64::from(self.character.hp)*i64::from(next.hp)/i64::from(before.hp)).clamp(1,i64::from(next.hp)) as i32;
            self.character.mp=(i64::from(self.character.mp)*i64::from(next.mp)/i64::from(before.mp)).clamp(0,i64::from(next.mp)) as i32;
            self.character.balance_respec_available=false;
            return Ok(vec!["已使用一次免费重置，全部属性点退回，气血和灵力按比例保留。".into()]);
        }
        if command.action==Action::SchoolJoin {
            if self.battle.is_some(){return Err("BATTLE_ACTIVE");}
            if command.battle_id.is_some()||command.attributes.is_some()||command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
            if command.expected_revision.as_deref()!=Some(&self.character.state_revision){return Err("STALE_SCHOOL");}
            if self.character.school!=3{return Err("SCHOOL_ALREADY_JOINED");}
            if context.map_id!="qingyun_trail"{return Err("INVALID_SCHOOL_NPC");}
            let npc=context.target_cell.ok_or("INVALID_SCHOOL_NPC")?;
            if (npc[0]-context.cell[0]).abs()+(npc[1]-context.cell[1]).abs()>2{return Err("RESIDENT_TOO_FAR");}
            let school=match command.target.as_deref(){Some("emei")=>0,Some("huajian")=>1,Some("kunlun")=>2,_=>return Err("INVALID_SCHOOL")};
            self.character.school=school;
            return Ok(vec![format!("经清微道人引荐，你已正式拜入{}。技能暂按职业和等级开放，不受门派限制。",["峨眉派","花涧派","昆仑派"][school as usize])]);
        }
        self.ai.respawns.retain(|_,deadline|*deadline>unix_ms());
        if matches!(command.action,Action::AiTravel|Action::AiAccept|Action::AiClaim|Action::AiInteract|Action::AiRestore) {
            if self.battle.is_some(){return Err("BATTLE_ACTIVE");}
            if command.battle_id.is_some()||command.expected_revision.is_some()||command.attributes.is_some()||command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
            let id=command.target.as_deref().ok_or("AI_INVALID_TARGET")?;
            let near=|point:[i32;2]| (point[0]-context.cell[0]).abs()+(point[1]-context.cell[1]).abs()<=2;
            if command.action==Action::AiTravel {
                let at_exit=crate::ai_world::map(&context.map_id).is_some()&&crate::ai_world::exit_target(&context.map_id,context.cell).as_deref()==Some(id);
                if !at_exit&&!near(crate::ai_world::station(&context.map_id)){return Err("PORTAL_TOO_FAR");}
                let map=crate::world_map::WorldMap::load(id).ok_or("AI_INVALID_TARGET")?;
                if id!="qingyun_trail"&&crate::ai_world::map(id).is_none(){return Err("AI_INVALID_TARGET");}
                if id==context.map_id{return Err("AI_SAME_MAP");}
                self.character.map_id=id.into();self.character.cell_x=map.spawn[0];self.character.cell_y=map.spawn[1];
                return Ok(vec!["已沿蜀山驿路抵达。AI生成场景与任务，不是原版恢复内容。".into()]);
            }
            let point=crate::ai_world::target_cell(&context.map_id,id).ok_or("AI_INVALID_TARGET")?;
            if !near(point){return Err("RESIDENT_TOO_FAR");}
            return match command.action {
                Action::AiAccept=>{self.ai.accept(id,&context.map_id,self.character.level)?;Ok(vec!["已接取AI生成任务，请按目标顺序行动。".into()])},
                Action::AiClaim=>{let (gold,xp)=self.ai.claim(id)?;self.rewards(gold,xp)?;Ok(vec![format!("AI生成任务完成，获得{gold}铜钱、{xp}修为。")])},
                Action::AiRestore=>{
                    if !id.ends_with("_guide"){return Err("AI_INVALID_TARGET");}
                    self.restore();Ok(vec!["巡山人以灵泉为你恢复了元气。".into()])
                },
                Action::AiInteract=>{
                    if crate::ai_world::resident(id).is_none_or(|r|r["kind"]!="npc"){return Err("AI_INVALID_TARGET");}
                    if !self.ai.event("interact",id){return Err("AI_NO_OBJECTIVE");}
                    Ok(vec!["已记录此处见闻，任务目标更新。".into()])
                },
                _=>unreachable!()
            };
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
            let bag_count=self.bag_count();
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
                    if item.effect==crate::shop::ItemEffect::ResetAttributes {
                        if crate::attributes::unallocated(&self.allocated){return Err("NO_ALLOCATED_ATTRIBUTES");}
                        let before=self.stats();self.allocated=[0;5];let next=self.stats();
                        self.character.hp=(i64::from(self.character.hp)*i64::from(next.hp)/i64::from(before.hp)).clamp(1,i64::from(next.hp)) as i32;
                        self.character.mp=(i64::from(self.character.mp)*i64::from(next.mp)/i64::from(before.mp)).clamp(0,i64::from(next.mp)) as i32;
                    }else{
                        let limits=self.stats();
                        if (item.restore_hp==0||self.character.hp>=limits.hp)&&(item.restore_mp==0||self.character.mp>=limits.mp){return Err("HP_FULL");}
                        self.character.hp=(self.character.hp+item.restore_hp).min(limits.hp);
                        self.character.mp=(self.character.mp+item.restore_mp).min(limits.mp);
                    }
                }
                if id=="potion"{self.potions-=count;}else if current==count{self.quantities.remove(id);self.gear.remove(id);}else{self.quantities.insert(id.into(),current-count);}
                self.equipped=self.gear.get("sword")==Some(&true);self.weapon_owned=self.gear.contains_key("sword");
                return Ok(vec![format!("已{}{}×{}。",if command.action==Action::Use{"使用"}else{"丢弃"},item.name,count)]);
            }
            if !item.equipment(){return Err("INVALID_EQUIPMENT");}
            if command.action==Action::Equip {
                if let Some(code)=item.equip_error(self.character.job,self.character.gender){return Err(code);}
            }
            let on=command.action==Action::Equip;
            if self.gear.get(id)==Some(&on){return Err("EQUIPMENT_UNCHANGED");}
            if !on&&bag_count>=60{return Err("BAG_FULL");}
            if on{self.loot.empty_slot(&item.slot);for (other,value) in &mut self.gear{if crate::shop::item(other).is_some_and(|i|i.slot==item.slot){*value=false;}}}
            self.gear.insert(id.into(),on);self.equipped=self.gear.get("sword")==Some(&true);
            return Ok(vec![format!("已{}{}。",if on{"装备"}else{"卸下"},item.name)]);
        }
        if command.quantity.is_some(){return Err("INVALID_PVE_COMMAND");}
        if command.action == Action::Transfer {
            if crate::ai_world::map(&context.map_id).is_some(){return Err("INVALID_PORTAL");}
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
                    if !self.loot.can_fight(){return Err("LOOT_STORAGE_FULL");}
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
                    if self.ai.respawns.get(&definition.id).is_some_and(|t|*t>unix_ms()){return Err("MONSTER_RESPAWNING");}
                    if self.character.quest_stage == 0 && crate::ai_world::map(&context.map_id).is_none() {
                        return Err("QUEST_REQUIRED");
                    }
                    let elite=self.hunt_pressure.note(&context.map_id,&definition.art);
                    if elite && command.encounter_version!=Some(2) {return Err("CLIENT_UPDATE_REQUIRED");}
                    let name = definition.name.clone();
                    let frozen=self.stats();
                    // Clients must opt into formation rendering; old clients retain solo-v1.
                    if command.encounter_version.is_none(){
                        let definition=if self.character.balance_revision==1{crate::progression::monster(crate::skill_balance::monster(definition))}else{definition};
                        let mut battle=Battle::new(definition,self.character.hp,self.character.mp,self.potions);
                        if frozen.balance.is_some(){battle.frozen_stats=Some(frozen);}
                        self.battle=Some(battle);
                        return Ok(vec![format!("与{name}的遭遇战开始。")]);
                    }
                    let mut pool:Vec<_>=population::definitions_for(&context.map_id).into_iter().filter(|d|d.id!=definition.id&&d.kind!="npc"&&d.kind!="boss"&&(d.level-definition.level).abs()<=3&&!self.respawns.get(&d.id).is_some_and(|t|*t>unix_ms())&&!self.ai.respawns.get(&d.id).is_some_and(|t|*t>unix_ms())).collect();
                    use rand::seq::SliceRandom;
                    pool.shuffle(&mut rand::thread_rng());
                    let count=crate::monster_combat::solo_count(rand::thread_rng().gen_range(0..100));
                    let mut sources=vec![definition.clone()];sources.extend(pool.iter().take(count-1).cloned());
                    if definition.kind!="boss"{pool.push(definition);}
                    while sources.len()<count&&!pool.is_empty(){sources.push(pool.choose(&mut rand::thread_rng()).unwrap().clone());}
                    let c=&self.character;
                    let fighter=crate::team_rules::Fighter{id:c.id,name:c.display_name.clone(),job:c.job,gender:c.gender,school:c.school,level:c.level,appearance:self.loot.look(crate::shop::appearance(&self.gear)),stats:frozen,hp:c.hp,mp:c.mp,potions:self.potions,effects:crate::skills::State::new(c.job,c.school,c.level,c.level),guarding:false};
                    let mut battle=Battle::new_formation(context.map_id.clone(),fighter,sources,unix_ms());
                    if elite {
                        let arena=battle.formation.as_mut().unwrap();arena.empower_hunt();
                        crate::monster_combat::empower(&mut battle.enemy,1);battle.enemy_hp=arena.enemies[0].hp;
                    }
                    let lines=battle.formation.as_ref().unwrap().lines.clone();
                    self.battle=Some(battle);
                    if elite {return Ok(lines);}
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
                let mut lines = if battle.formation.is_some(){battle.turn_formation(action,command.target.as_deref(),command.enemy_slot.as_deref(),unix_ms(),rng.gen_range(0..100))?}else{
                    battle.turn_selected(
                    action,
                    self.character.job,
                    self.character.school,
                    self.character.level,
                    stats,
                    rng.gen_range(-2..=2),
                    rng.gen_range(-2..=2),
                    command.target.as_deref(),
                    rng.gen_range(0..100),
                )?
                };
                self.character.hp = battle.hp.max(1);
                self.character.mp = battle.mp;
                self.potions = battle.potions;
                if battle.outcome == "victory" {
                    if let Some(arena)=battle.formation.as_ref().filter(|a|a.elite_hunt()) {
                        self.hunt_pressure.cleared(&arena.map_id,&arena.enemies[0].definition.art);
                    }
                    let defeated=battle.defeated_enemies();
                    let loot_enabled=battle.loot_revision>=1;
                    let boss_loot=defeated.iter().any(|d|d.kind=="boss"||d.id=="boss")||battle.formation.as_ref().is_some_and(|a|a.elite_hunt());
                    let loot_level=defeated.iter().map(|d|d.level).max().unwrap_or(1).min(self.character.level);
                    let gold=defeated.iter().map(|d|d.gold).sum();let xp=defeated.iter().map(|d|d.xp).sum();
                    let killed_boss=defeated.iter().any(|d|d.id=="boss");
                    let mut recorded=std::collections::HashSet::new();
                    for enemy in defeated {
                        if !recorded.insert(enemy.id.clone()){continue;}
                        if crate::ai_world::resident(&enemy.id).is_some(){self.ai.event("kill",&enemy.id);self.ai.respawns.insert(enemy.id.clone(),unix_ms()+MONSTER_RESPAWN_MS);}
                        else{self.defeated|=pve_rules::mask(&enemy.id).ok_or("INVALID_RESIDENT")?;self.respawns.insert(enemy.id,unix_ms()+MONSTER_RESPAWN_MS);}
                    }
                    if self.character.quest_stage == 1 && self.defeated & 7 == 7 {
                        self.character.quest_stage = 2;
                        lines.push("三只山狼已清除，请返回清微道人处领取奖励。".into());
                    }
                    if killed_boss && self.character.quest_stage == 3 {
                        self.character.quest_stage = 4;
                        lines.push("赤焰妖王已被击败，古剑遗迹的妖气消散了。".into());
                    }
                    self.rewards(gold, xp)?;
                    if loot_enabled{
                        let gained=self.loot.reward(self.character.job,self.character.gender,loot_level,boss_loot,self.bag_count(),rand::random());
                        lines.push(format!("获得{}件装备及炼材{}、精华{}；满包装备存入暂存。",gained.len(),if boss_loot{crate::progression::n("boss_scrap")}else{crate::progression::n("victory_scrap")},if boss_loot{crate::progression::n("boss_essence")}else{0}));
                    }
                    lines.push(format!("获得{gold}铜钱、{xp}修为。"));
                } else if battle.outcome == "defeat" {
                    self.die(context.cell)?;
                    lines.push("你在本地图复活点化为灵魂，请返回坟堆寻回尸体。".into());
                }
                Ok(lines)
            }
        }
    }
    fn die(&mut self, cell:[i32;2])->Result<(),&'static str>{
        if self.character.corpse.is_some(){return Err("SOUL_STATE");}
        let corpse=crate::soul::Corpse::new(&self.character.map_id,cell)?;
        let map=crate::world_map::WorldMap::load(&self.character.map_id).ok_or("INVALID_CORPSE_POSITION")?;
        self.character.corpse=Some(Json(corpse));
        self.character.hp=0;self.character.mp=0;
        self.character.cell_x=map.spawn[0];self.character.cell_y=map.spawn[1];
        Ok(())
    }
    fn bag_count(&self)->usize{self.gear.values().filter(|on|!**on).count()+(self.potions.max(0) as usize).div_ceil(99)+self.loot.extra_bag()}
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
        || command.target.as_ref().is_some_and(|id| id.len() > if matches!(command.action,Action::Revive|Action::GearEquip|Action::GearUnequip|Action::GearClaim|Action::GearSalvage|Action::GearReroll|Action::GearUpgrade){36}else{32})
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
    let target = command.target.as_deref().map(|v| if crate::ai_world::map(v).is_some() || crate::ai_world::quest(v).is_some() || crate::ai_world::resident(v).is_some() || crate::shop::item(v).is_some() || crate::skills::item(v).is_some() || ["sword","qingwei","wolf_a","wolf_b","wolf_c","spirit","guardian","boss","ruins","trail_gate"].contains(&v) { v } else { "[invalid]" });
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
    let was_soul=original.character.corpse.is_some();
    let before = crate::security::state_summary(&original.state());
    let team_active:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members m JOIN team_battles b ON b.team_id=m.team_id AND b.active WHERE m.character_id=$1)").bind(context.character).fetch_one(&mut *tx).await.map_err(database)?;
    let in_team:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members WHERE character_id=$1)").bind(context.character).fetch_one(&mut *tx).await.map_err(database)?;
    let applied = if team_active {Err("TEAM_BATTLE_ACTIVE")}else if context.duel_active {Err("DUEL_ACTIVE")}else if in_team&&command.action==Action::Challenge{Err("TEAM_CHALLENGE_REQUIRED")}else{loaded.apply(command, context)};
    if applied.is_err() {
        loaded = original;
    }
    if applied.is_ok() {
        loaded.loot.sync_legacy(&loaded.gear,loaded.character.job,loaded.character.gender);
        let maxima=loaded.stats();
        loaded.character.hp=loaded.character.hp.min(maxima.hp);
        loaded.character.mp=loaded.character.mp.min(maxima.mp);
        if !loaded.hunt_pressure.valid(){return Err(unavailable());}
        if !loaded.loot.valid(loaded.character.job,loaded.character.gender){return Err(unavailable());}
        sqlx::query("UPDATE characters SET loot_state=$2 WHERE id=$1").bind(context.character).bind(Json(&loaded.loot)).execute(&mut *tx).await.map_err(database)?;
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
        if loaded.character.map_id != context.map_id {loaded.hunt_pressure=Default::default();}
        if loaded.character.map_id != context.map_id || (!was_soul&&loaded.character.corpse.is_some()) {
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
        let revision:i64=sqlx::query_scalar("UPDATE characters SET level=$2,xp=$3,gold=$4,hp=$5,mp=$6,quest_stage=$7,defeated_mask=$8,active_battle_id=$9,allocated_attributes=$10,monster_respawns=$11,ai_progress=$12,school=$13,corpse=$14,balance_respec_available=$15,hunt_pressure=$16,state_revision=state_revision+1 WHERE id=$1 RETURNING state_revision")
            .bind(c.id).bind(c.level).bind(c.xp).bind(c.gold).bind(c.hp).bind(c.mp).bind(c.quest_stage).bind(loaded.defeated).bind(active).bind(loaded.allocated.to_vec()).bind(Json(&loaded.respawns))
            .bind(Json(&loaded.ai)).bind(c.school).bind(&c.corpse).bind(c.balance_respec_available).bind(Json(&loaded.hunt_pressure)).fetch_one(&mut *tx).await.map_err(database)?;
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

/// Uses the same character, equipment, skill and respawn rules as solo PvE.
pub(crate) async fn team_fighter(tx:&mut Transaction<'_,Postgres>,context:&Context)->Result<(crate::team_rules::Fighter,std::collections::HashSet<String>),AuthError>{
    let a=load(tx,context).await?;
    if a.character.corpse.is_some(){return Err(AuthError(StatusCode::CONFLICT,"SOUL_STATE"));}
    if !a.loot.can_fight(){return Err(AuthError(StatusCode::CONFLICT,"LOOT_STORAGE_FULL"));}
    if a.battle.is_some()||context.duel_active{return Err(AuthError(StatusCode::CONFLICT,"TEAM_BUSY"));}
    if context.map_id!=a.character.map_id||context.moving{return Err(AuthError(StatusCode::CONFLICT,"TEAM_NOT_READY"));}
    // Freeze the actual encounter origin, not an older periodic position save.
    sqlx::query("UPDATE characters SET cell_x=$2,cell_y=$3,position_revision=$4 WHERE id=$1 AND owner_epoch=$5 AND map_id=$6 AND position_revision<=$4")
        .bind(a.character.id).bind(context.cell[0]).bind(context.cell[1]).bind(context.position_revision as i64).bind(context.owner).bind(&context.map_id).execute(&mut **tx).await.map_err(database)?;
    if crate::ai_world::map(&context.map_id).is_none()&&a.character.quest_stage==0{return Err(AuthError(StatusCode::CONFLICT,"QUEST_REQUIRED"));}
    let c=&a.character;
    let unavailable=a.respawns.iter().chain(a.ai.respawns.iter()).filter(|(_,t)|**t>unix_ms()).map(|(id,_)|id.clone()).collect();
    Ok((crate::team_rules::Fighter{id:c.id,name:c.display_name.clone(),job:c.job,gender:c.gender,school:c.school,level:c.level,stats:a.stats(),appearance:a.loot.look(crate::shop::appearance(&a.gear)),hp:c.hp,mp:c.mp,potions:a.potions,effects:crate::skills::State::new(c.job,c.school,c.level,c.level),guarding:false},unavailable))
}
pub(crate) async fn team_save(tx:&mut Transaction<'_,Postgres>,f:&crate::team_rules::Fighter,b:&crate::team_rules::Battle,settle:bool)->Result<(),AuthError>{
    let account=sqlx::query_scalar("SELECT account_id FROM characters WHERE id=$1").bind(f.id).fetch_one(&mut **tx).await.map_err(database)?;
    let mut a=load_character(tx,f.id,account,None).await?;
    a.character.hp=f.hp.max(1).min(a.stats().hp);a.character.mp=f.mp.min(a.stats().mp);a.potions=f.potions;
    if settle&&b.outcome=="victory"{
        if b.elite_hunt(){a.hunt_pressure.cleared(&b.map_id,&b.enemies[0].definition.art);}
        let mut ids=std::collections::HashSet::new();
        for e in &b.enemies{
            if !ids.insert(e.definition.id.clone()){continue;}
            if crate::ai_world::resident(&e.definition.id).is_some(){a.ai.event("kill",&e.definition.id);a.ai.respawns.insert(e.definition.id.clone(),unix_ms()+MONSTER_RESPAWN_MS);}
            else if let Some(mask)=pve_rules::mask(&e.definition.id){a.defeated|=mask;a.respawns.insert(e.definition.id.clone(),unix_ms()+MONSTER_RESPAWN_MS);}
            if e.definition.id=="boss"&&a.character.quest_stage==3{a.character.quest_stage=4;}
        }
        if a.character.quest_stage==1&&a.defeated&7==7{a.character.quest_stage=2;}
        let index=b.fighters.iter().position(|p|p.id==f.id).unwrap() as i32;
        let n=b.fighters.len()as i32;
        let total_gold:i32=b.enemies.iter().map(|e|e.definition.gold).sum();
        let total_xp:i32=b.enemies.iter().map(|e|e.definition.xp).sum();
        a.rewards(total_gold/n+i32::from(index<total_gold%n),total_xp/n+i32::from(index<total_xp%n)).map_err(|c|AuthError(StatusCode::CONFLICT,c))?;
        if b.loot_revision>=1{
            let boss=b.elite_hunt()||b.enemies.iter().any(|e|e.definition.kind=="boss"||e.definition.id=="boss");
            crate::progression::credit(&mut a.loot,boss);
        }
    }
    if settle&&f.hp==0&&a.character.corpse.is_none(){
        let point=[a.character.cell_x,a.character.cell_y];
        a.die(point).map_err(|code|AuthError(StatusCode::CONFLICT,code))?;
    }
    sqlx::query("UPDATE characters SET loot_state=$2 WHERE id=$1").bind(f.id).bind(Json(&a.loot)).execute(&mut **tx).await.map_err(database)?;
    sqlx::query("UPDATE characters SET hp=$2,mp=$3,level=$4,xp=$5,gold=$6,quest_stage=$7,defeated_mask=$8,monster_respawns=$9,ai_progress=$10,position_revision=position_revision+CASE WHEN corpse IS NULL AND $11::jsonb IS NOT NULL THEN 1 ELSE 0 END,corpse=$11,cell_x=$12,cell_y=$13,hunt_pressure=$14,state_revision=state_revision+1 WHERE id=$1")
        .bind(f.id).bind(a.character.hp).bind(a.character.mp).bind(a.character.level).bind(a.character.xp).bind(a.character.gold).bind(a.character.quest_stage).bind(a.defeated).bind(Json(a.respawns)).bind(Json(a.ai)).bind(a.character.corpse).bind(a.character.cell_x).bind(a.character.cell_y).bind(Json(&a.hunt_pressure)).execute(&mut **tx).await.map_err(database)?;
    if a.potions==0{sqlx::query("DELETE FROM inventory_items WHERE character_id=$1 AND definition_id='potion'").bind(f.id).execute(&mut **tx).await.map_err(database)?;}
    else{sqlx::query("INSERT INTO inventory_items(id,character_id,definition_id,quantity) VALUES($1,$2,'potion',$3) ON CONFLICT(character_id,definition_id) DO UPDATE SET quantity=EXCLUDED.quantity").bind(Uuid::new_v4()).bind(f.id).bind(a.potions).execute(&mut **tx).await.map_err(database)?;}
    Ok(())
}

pub(crate) async fn team_loot_pool(tx:&mut Transaction<'_,Postgres>,b:&crate::team_rules::Battle,now:i64)->Result<crate::team_loot::Pool,AuthError>{
    let ids:Vec<_>=b.fighters.iter().map(|f|f.id).collect();
    let rows=sqlx::query("SELECT id,loot_state FROM characters WHERE id=ANY($1) ORDER BY id FOR UPDATE").bind(&ids).fetch_all(&mut **tx).await.map_err(database)?;
    let mut states=std::collections::BTreeMap::new();
    for row in rows{let state:crate::loot::State=serde_json::from_value(row.get::<Json<Value>,_>("loot_state").0).map_err(|_|unavailable())?;states.insert(row.get::<Uuid,_>("id"),state);}
    let mut scratch=crate::loot::State::default();
    let boss=b.elite_hunt()||b.enemies.iter().any(|e|e.definition.kind=="boss"||e.definition.id=="boss");
    scratch.kills=if states.values().any(|s|(s.kills+1)%crate::progression::n("normal_pity")==0){crate::progression::n("normal_pity")-1}else{states.values().map(|s|s.kills).max().unwrap_or(0)};
    scratch.bosses=if states.values().any(|s|(s.bosses+1)%crate::progression::n("boss_pity")==0){crate::progression::n("boss_pity")-1}else{states.values().map(|s|s.bosses).max().unwrap_or(0)};
    scratch.focus=states.get(&b.fighters[0].id).ok_or_else(unavailable)?.focus.clone();
    let f=&b.fighters[rand::thread_rng().gen_range(0..b.fighters.len())];
    let level=b.enemies.iter().map(|e|e.definition.level).max().unwrap_or(1).min(f.level);
    scratch.reward(f.job,f.gender,level,boss,0,rand::random());
    Ok(crate::team_loot::Pool::new(scratch.items,&b.fighters,now))
}
pub(crate) async fn team_loot_award(tx:&mut Transaction<'_,Postgres>,id:Uuid,item:&crate::loot::Item)->Result<(),AuthError>{
    let account=sqlx::query_scalar("SELECT account_id FROM characters WHERE id=$1").bind(id).fetch_one(&mut **tx).await.map_err(database)?;
    let mut a=load_character(tx,id,account,None).await?;
    if !item.valid(a.character.job,a.character.gender)||item.level>a.character.level{return Err(unavailable());}
    if a.loot.items.iter().chain(a.loot.pending.iter()).any(|i|i.id==item.id){return Err(unavailable());}
    a.loot.skins.insert(item.template.clone());
    if a.bag_count()<60{a.loot.items.push(item.clone());}else if a.loot.pending.len()<20{a.loot.pending.push(item.clone());}else{return Err(AuthError(StatusCode::CONFLICT,"LOOT_STORAGE_FULL"));}
    if !a.loot.valid(a.character.job,a.character.gender){return Err(unavailable());}
    sqlx::query("UPDATE characters SET loot_state=$2,state_revision=state_revision+1 WHERE id=$1").bind(id).bind(Json(a.loot)).execute(&mut **tx).await.map_err(database)?;
    Ok(())
}

/// Called only after actual participants are validated and locked, inside the battle transaction.
pub(crate) async fn team_hunt(tx:&mut Transaction<'_,Postgres>,ids:&[Uuid],map:&str,species:&str)->Result<bool,AuthError>{
    let mut elite=false;
    for id in ids {
        let value:Json<Value>=sqlx::query_scalar("SELECT hunt_pressure FROM characters WHERE id=$1 FOR UPDATE").bind(id).fetch_one(&mut **tx).await.map_err(database)?;
        let mut pressure:crate::monster_combat::HuntPressure=serde_json::from_value(value.0).map_err(|_|unavailable())?;
        if !pressure.valid(){return Err(unavailable());}
        elite|=pressure.note(map,species);
        sqlx::query("UPDATE characters SET hunt_pressure=$2 WHERE id=$1").bind(id).bind(Json(pressure)).execute(&mut **tx).await.map_err(database)?;
    }
    Ok(elite)
}
