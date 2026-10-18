//! Two character business gates are always acquired in UUID order.
use super::*;
use crate::duel::{Command, Fighter, REJECT_SECONDS};
use rand::Rng;

impl WorldHub {
    pub(super) fn duel_enable(&self, owner: &Ownership, enabled: bool) {
        if let Some(actor) = self
            .data
            .lock()
            .expect("world state")
            .actors
            .get_mut(&owner.id)
            .filter(|a| Self::owned(a, owner))
        {
            actor.duel_enabled = enabled;
        }
    }
    fn duel_owner(&self, id: Uuid) -> Result<Ownership, AuthError> {
        let state = self.data.lock().expect("world state");
        let a = state
            .actors
            .get(&id)
            .filter(|a| a.connected && a.duel_enabled)
            .ok_or(error(409, "DUEL_PLAYER_OFFLINE"))?;
        Ok(Ownership {
            business: a.business.clone(),
            id: a.id,
            session: a.session,
            game: a.game,
            chat_start_seq: a.chat_start_seq,
            epoch: a.epoch,
            owner: a.owner,
            joined_revision: state.revision,
            map_id: a.map_id.clone(),
        })
    }
    pub(super) async fn duel_command(
        &self,
        auth: &AuthService,
        owner: &Ownership,
        c: &Command,
    ) -> Value {
        let response = |ok: bool, code: &str, retry: u64| json!({"type":"duel.result","request_id":c.request_id,"ok":ok,"code":code,"retry_after_ms":retry});
        if !c.valid() {
            return response(false, "INVALID_DUEL_COMMAND", 0);
        }
        {
            let mut state = self.data.lock().expect("world state");
            if let Some(cached) = state.duels.cached(owner.id, c) {
                return cached;
            }
            if !state.duels.admit(owner.id, Instant::now()) {
                return response(false, "DUEL_RATE_LIMITED", 200);
            }
        }
        let applied=async {
            let peer={
                let state=self.data.lock().expect("world state");
                match c.action.as_str(){
                    "invite"=>c.target.ok_or(("INVALID_DUEL_COMMAND",0))?,
                    "accept"|"reject"|"cancel"=>{
                        let offer=state.duels.offers.get(&c.invite_id.unwrap()).ok_or(("DUEL_INVITE_EXPIRED",0))?;
                        if (c.action=="cancel"&&offer.from!=owner.id)||(c.action!="cancel"&&offer.to!=owner.id){return Err(("DUEL_FORBIDDEN",0));}
                        if offer.from==owner.id{offer.to}else{offer.from}
                    },
                    _=>{let id=state.duels.slots.get(&owner.id).ok_or(("DUEL_NOT_FOUND",0))?;let b=&state.duels.battles[id];b.fighters.iter().find(|f|f.id!=owner.id).unwrap().id},
                }
            };
            if peer==owner.id{return Err(("DUEL_SELF",0));}
            let mut gates={let state=self.data.lock().expect("world state");[owner.id,peer].into_iter().map(|id|state.actors.get(&id).map(|a|(id,a.business.clone())).ok_or(("DUEL_PLAYER_OFFLINE",0))).collect::<Result<Vec<_>,_>>()?};
            gates.sort_by_key(|(id,_)|*id);
            let mut guards=Vec::new();for (_,gate) in gates{guards.push(gate.lock_owned().await);}
            if !self.current(owner){return Err(("SESSION_REPLACED",0));}
            if matches!(c.action.as_str(),"invite"|"accept"){
                let state=self.data.lock().expect("world state");
                let a=state.actors.get(&owner.id).unwrap();let b=state.actors.get(&peer).ok_or(("DUEL_PLAYER_OFFLINE",0))?;
                if !a.duel_enabled||!b.duel_enabled||!b.connected{return Err(("DUEL_PLAYER_OFFLINE",0));}
                if a.map_id!=b.map_id{return Err(("DUEL_DIFFERENT_MAP",0));}
                if a.in_battle||b.in_battle||state.duels.active(a.id)||state.duels.active(b.id)||state.team_busy.contains(&a.id)||state.team_busy.contains(&b.id){return Err(("DUEL_BUSY",0));}
            }
            match c.action.as_str(){
                "invite"=>{
                    let retry: i64=sqlx::query_scalar("SELECT COALESCE(MAX(CEIL(EXTRACT(EPOCH FROM (expires_at-clock_timestamp()))*1000)::bigint),0) FROM duel_invite_cooldowns WHERE inviter_id=$1 AND target_id=$2 AND expires_at>clock_timestamp()")
                        .bind(owner.id).bind(peer).fetch_one(auth.pool()).await.map_err(|_|("DATABASE_UNAVAILABLE",0))?;
                    if retry>0{return Err(("DUEL_REJECT_COOLDOWN",retry as u64));}
                    let mut state=self.data.lock().expect("world state");
                    let from=state.actors[&owner.id].display_name.clone();let to=state.actors[&peer].display_name.clone();
                    state.duels.invite(owner.id,peer,from,to,Instant::now()).map_err(|e|(e,0))?;
                },
                "reject"=>{
                    // Commit the ordered-pair cooldown before acknowledging rejection.
                    let mut tx=auth.pool().begin().await.map_err(|_|("DATABASE_UNAVAILABLE",0))?;
                    sqlx::query("INSERT INTO duel_invite_cooldowns(inviter_id,target_id,expires_at) VALUES($1,$2,clock_timestamp()+$3*interval '1 second') ON CONFLICT(inviter_id,target_id) DO UPDATE SET expires_at=EXCLUDED.expires_at")
                        .bind(peer).bind(owner.id).bind(REJECT_SECONDS as f64).execute(&mut *tx).await.map_err(|_|("DATABASE_UNAVAILABLE",0))?;
                    sqlx::query("DELETE FROM duel_invite_cooldowns WHERE expires_at<=clock_timestamp()").execute(&mut *tx).await.map_err(|_|("DATABASE_UNAVAILABLE",0))?;
                    tx.commit().await.map_err(|_|("DATABASE_UNAVAILABLE",0))?;
                    self.data.lock().expect("world state").duels.remove_offer(c.invite_id.unwrap(),"对方已拒绝决斗，邀请者需等待5分钟后才能再次邀请该玩家。");
                },
                "cancel"=>self.data.lock().expect("world state").duels.remove_offer(c.invite_id.unwrap(),"邀请者已取消决斗邀请。"),
                "accept"=>{
                    let other=self.duel_owner(peer).map_err(|e|(e.1,0))?;
                    let from_context=self.pve_context(&other,None).map_err(|e|(e.1,0))?;
                    let to_context=self.pve_context(owner,None).map_err(|e|(e.1,0))?;
                    let from=crate::pve::snapshot(auth,&from_context).await.map_err(|e|(e.1,0))?;
                    let to=crate::pve::snapshot(auth,&to_context).await.map_err(|e|(e.1,0))?;
                    let mut state=self.data.lock().expect("world state");
                    if !state.actors.get(&peer).is_some_and(|a|Self::owned(a,&other))||!state.actors.get(&owner.id).is_some_and(|a|Self::owned(a,owner)){return Err(("DUEL_PLAYER_OFFLINE",0));}
                    let fighters=[Fighter::from_snapshot(&from,state.actors[&peer].appearance).map_err(|e|(e,0))?,Fighter::from_snapshot(&to,state.actors[&owner.id].appearance).map_err(|e|(e,0))?];
                    let first=rand::random::<bool>() as usize;
                    state.duels.start(c.invite_id.unwrap(),owner.id,fighters,first,Instant::now()).map_err(|e|(e,0))?;
                    for who in [owner.id,peer]{state.actors.get_mut(&who).unwrap().motion.stop();}state.revision+=1;
                },
                _=>self.data.lock().expect("world state").duels.act(owner.id,c,Instant::now(),rand::thread_rng().gen_range(0..100)).map_err(|e|(e,0))?,
            }
            Ok(())
        }.await;
        let result = match applied {
            Ok(()) => response(true, "OK", 0),
            Err((code, retry)) => response(false, code, retry),
        };
        self.data
            .lock()
            .expect("world state")
            .duels
            .remember(owner.id, c, result.clone());
        crate::security::connection_event(auth,owner.session,owner.id,&format!("duel.{}",c.action),result["code"].as_str().unwrap_or("OK"),json!({"request_id":c.request_id,"target":c.target,"invite_id":c.invite_id,"battle_id":c.battle_id,"accepted":result["ok"]})).await;
        result
    }
}
