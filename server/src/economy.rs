//! Server-owned escrow. Currency, UUID equipment, receipts and deliveries commit together.
use crate::{AppState,auth::{self,AuthError,Peer},loot};
use axum::{Json,extract::{State,rejection::JsonRejection},http::{HeaderMap,StatusCode}};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sha2::{Digest,Sha256};
use sqlx::{Postgres,Transaction,Row,types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;

type Tx<'a> = Transaction<'a,Postgres>;
const MAX_PRICE:i32=1_000_000_000;
#[derive(Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Command{
    character_id:Uuid,action:String,
    #[serde(default)] operation_id:Option<Uuid>,
    #[serde(default)] target:Option<Uuid>,
    #[serde(default)] revision:i64,
    #[serde(default)] amount:i32,
    #[serde(default)] buyout:i32,
    #[serde(default)] hours:i32,
    #[serde(default)] page:i32,
    #[serde(default)] scope:String,
    #[serde(default)] slot:String,
    #[serde(default)] quality:String,
    #[serde(default="any_job")] job:i16,
    #[serde(default)] items:Vec<Uuid>,
}
fn any_job()->i16{-1}
fn db(e:sqlx::Error)->AuthError{crate::observability::database_error(&e,"economy");AuthError(StatusCode::SERVICE_UNAVAILABLE,"DATABASE_UNAVAILABLE")}
fn err(code:&'static str)->AuthError{AuthError(StatusCode::CONFLICT,code)}
fn target(c:&Command)->Result<Uuid,AuthError>{c.target.ok_or_else(||err("INVALID_REQUEST"))}
async fn lock(tx:&mut Tx<'_>)->Result<(),AuthError>{
    sqlx::query("SET LOCAL lock_timeout='3s'").execute(&mut **tx).await.map_err(db)?;
    sqlx::query("SELECT pg_advisory_xact_lock(773913020)").execute(&mut **tx).await.map_err(db)?;Ok(())
}
struct Wallet{loot:loot::State,gold:i32,bag:usize}
async fn wallet(tx:&mut Tx<'_>,id:Uuid)->Result<Wallet,AuthError>{
    let row=sqlx::query("SELECT loot_state,gold,job,gender,corpse,active_battle_id FROM characters WHERE id=$1 AND deleted_at IS NULL FOR UPDATE").bind(id).fetch_optional(&mut **tx).await.map_err(db)?.ok_or_else(||err("PLAYER_NOT_FOUND"))?;
    if row.get::<Option<DbJson<Value>>,_>("corpse").is_some(){return Err(err("SOUL_STATE"));}
    if row.get::<Option<Uuid>,_>("active_battle_id").is_some(){return Err(err("BATTLE_ACTIVE"));}
    let busy:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM team_members m JOIN team_battles b ON b.team_id=m.team_id WHERE m.character_id=$1 AND b.active)").bind(id).fetch_one(&mut **tx).await.map_err(db)?;
    if busy{return Err(err("BATTLE_ACTIVE"));}
    let loot:loot::State=serde_json::from_value(row.get::<DbJson<Value>,_>("loot_state").0).map_err(|_|err("PVE_STATE_UNAVAILABLE"))?;
    if !loot.valid(row.get("job"),row.get("gender")){return Err(err("PVE_STATE_UNAVAILABLE"));}
    let rows=sqlx::query("SELECT definition_id,quantity,equipped FROM inventory_items WHERE character_id=$1").bind(id).fetch_all(&mut **tx).await.map_err(db)?;
    let fixed:usize=rows.iter().map(|r|{let id:String=r.get("definition_id");let q:i32=r.get("quantity");if r.get::<bool,_>("equipped"){0}else if id=="potion"{((q+98)/99) as usize}else{1}}).sum();
    let bag=fixed+loot.extra_bag();Ok(Wallet{loot,gold:row.get("gold"),bag})
}
async fn save(tx:&mut Tx<'_>,id:Uuid,w:&Wallet)->Result<(),AuthError>{
    sqlx::query("UPDATE characters SET loot_state=$2,gold=$3,state_revision=state_revision+1 WHERE id=$1").bind(id).bind(DbJson(&w.loot)).bind(w.gold).execute(&mut **tx).await.map_err(db)?;Ok(())
}
async fn deliver(tx:&mut Tx<'_>,owner:Uuid,item:Option<&loot::Item>,gold:i32,reason:&str,source:Uuid)->Result<(),AuthError>{
    if item.is_none()&&gold==0{return Ok(());}
    sqlx::query("INSERT INTO economy_deliveries(id,character_id,item,gold,reason,source_id) VALUES($1,$2,$3,$4,$5,$6)").bind(Uuid::new_v4()).bind(owner).bind(item.map(DbJson)).bind(gold).bind(reason).bind(source).execute(&mut **tx).await.map_err(db)?;Ok(())
}
async fn finish(tx:&mut Tx<'_>,id:Uuid,status:&str,buyer:Option<Uuid>,price:i32)->Result<(),AuthError>{
    let r=sqlx::query("SELECT seller,item FROM auction_listings WHERE id=$1 AND status='open' FOR UPDATE").bind(id).fetch_optional(&mut **tx).await.map_err(db)?.ok_or_else(||err("AUCTION_CLOSED"))?;
    let seller:Uuid=r.get("seller");let item:loot::Item=serde_json::from_value(r.get::<DbJson<Value>,_>("item").0).map_err(|_|err("INVALID_EQUIPMENT"))?;
    deliver(tx,buyer.unwrap_or(seller),Some(&item),0,if buyer.is_some(){"auction_purchase"}else{"auction_return"},id).await?;
    if buyer.is_some(){deliver(tx,seller,None,price,"auction_sale",id).await?;}
    sqlx::query("UPDATE auction_listings SET status=$2,revision=revision+1 WHERE id=$1").bind(id).bind(status).execute(&mut **tx).await.map_err(db)?;Ok(())
}
async fn settle(tx:&mut Tx<'_>)->Result<(),AuthError>{
    let rows=sqlx::query("SELECT id,bidder,bid FROM auction_listings WHERE status='open' AND expires_at<=clock_timestamp() ORDER BY expires_at LIMIT 128 FOR UPDATE").fetch_all(&mut **tx).await.map_err(db)?;
    for r in rows{let bidder:Option<Uuid>=r.get("bidder");finish(tx,r.get("id"),if bidder.is_some(){"sold"}else{"expired"},bidder,r.get("bid")).await?;}
    Ok(())
}
pub(crate) fn start(state:&Arc<AppState>){
    let Some(auth)=state.auth.clone()else{return;};
    // No dependency on a buyer/seller remaining connected. Restart safely resumes escrow.
    tokio::spawn(async move{let mut tick=tokio::time::interval(std::time::Duration::from_secs(30));loop{tick.tick().await;let result=async{
        let mut tx=auth.pool().begin().await.map_err(db)?;lock(&mut tx).await?;settle(&mut tx).await?;tx.commit().await.map_err(db)
    }.await;if result.is_err(){tracing::warn!("economy settlement deferred; durable escrow retained");}}});
}
pub(crate) async fn command(State(state):State<Arc<AppState>>,peer:Peer,headers:HeaderMap,body:Result<Json<Command>,JsonRejection>)->Result<Json<Value>,AuthError>{
    let auth=auth::service(&state)?;auth.admit_social_peer(auth::peer_ip(peer))?;
    let token=auth::bearer(&headers)?;let account=auth.me(token).await?;auth.admit_social(account.id)?;
    let Json(c)=body.map_err(|_|err("INVALID_REQUEST"))?;
    if c.action.len()>32||c.scope.len()>16||c.slot.len()>16||c.quality.len()>16||!(0..=10000).contains(&c.page)||!(-1..=2).contains(&c.job)||c.items.len()>6{return Err(err("INVALID_REQUEST"));}
    let read=c.action=="snapshot";
    if !read&&c.operation_id.is_none_or(|id|id.get_version_num()!=4||id.get_variant()!=uuid::Variant::RFC4122){return Err(err("INVALID_REQUEST"));}
    let hub=state.world.as_ref().ok_or_else(||err("WORLD_UNAVAILABLE"))?;
    let mut tx=auth.pool().begin().await.map_err(db)?;lock(&mut tx).await?;auth.authorize_in(&mut tx,token).await?;
    let owned:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL)").bind(c.character_id).bind(account.id).fetch_one(&mut *tx).await.map_err(db)?;
    if !owned{return Err(AuthError(StatusCode::FORBIDDEN,"FORBIDDEN"));}
    let _gates=hub.team_guards(&[c.character_id]).await;hub.team_context(c.character_id)?;
    settle(&mut tx).await?;
    let mut result=json!({"ok":true,"code":"OK","replayed":false});
    if !read{
        let digest=Sha256::digest(serde_json::to_vec(&c).unwrap()).to_vec();
        let old=sqlx::query("SELECT request_digest,result FROM economy_receipts WHERE character_id=$1 AND operation_id=$2").bind(c.character_id).bind(c.operation_id).fetch_optional(&mut *tx).await.map_err(db)?;
        if let Some(old)=old{
            if old.get::<Vec<u8>,_>("request_digest")!=digest{return Err(err("IDEMPOTENCY_CONFLICT"));}
            result=old.get::<DbJson<Value>,_>("result").0;result["replayed"]=json!(true);
        }else{
            sqlx::query("SAVEPOINT economy_action").execute(&mut *tx).await.map_err(db)?;
            match apply(&mut tx,&c).await{Ok(id)=>result["id"]=json!(id),Err(e)=>{
                if e.0==StatusCode::SERVICE_UNAVAILABLE{return Err(e);}
                sqlx::query("ROLLBACK TO SAVEPOINT economy_action").execute(&mut *tx).await.map_err(db)?;result["ok"]=json!(false);result["code"]=json!(e.1);
            }}
            sqlx::query("INSERT INTO economy_receipts(character_id,operation_id,request_digest,result) VALUES($1,$2,$3,$4)").bind(c.character_id).bind(c.operation_id).bind(digest).bind(DbJson(&result)).execute(&mut *tx).await.map_err(db)?;
            crate::security::append(&mut *tx,crate::security::Event{account:Some(account.id),character:Some(c.character_id),session:None,operation:c.operation_id,action:&format!("economy.{}",c.action),outcome:if result["ok"]==true{"accepted"}else{"rejected"},code:result["code"].as_str().unwrap_or("OK"),details:json!({"target":c.target,"amount":c.amount,"item_ids":c.items,"result":result})}).await.map_err(db)?;
        }
    }
    result["operation_id"]=json!(c.operation_id);result["character_id"]=json!(c.character_id);
    result["market"]=snapshot(&mut tx,&c).await?;
    result["state"]=crate::pve::economy_snapshot(&mut tx,c.character_id,account.id).await?;
    tx.commit().await.map_err(db)?;hub.team_sync(&[c.character_id],None,true);Ok(Json(result))
}
async fn apply(tx:&mut Tx<'_>,c:&Command)->Result<Option<Uuid>,AuthError>{
    let mut w=wallet(tx,c.character_id).await?;
    match c.action.as_str(){
        "list"=>{
            if !(1..=MAX_PRICE).contains(&c.amount)||!(c.amount..=MAX_PRICE).contains(&c.buyout)||![6,12,24].contains(&c.hours){return Err(err("INVALID_AUCTION_PRICE"));}
            let count:i64=sqlx::query_scalar("SELECT count(*) FROM auction_listings WHERE seller=$1 AND status='open'").bind(c.character_id).fetch_one(&mut **tx).await.map_err(db)?;
            if count>=20{return Err(err("AUCTION_LIMIT"));}
            let item_id=target(c)?;let pos=w.loot.items.iter().position(|i|i.id==item_id).ok_or_else(||err("INSTANCE_NOT_OWNED"))?;
            let item=w.loot.items.remove(pos);if !item.tradable(){return Err(err("EQUIPMENT_BOUND"));}
            let d=item.definition();let job=item.legendary.as_deref().or(item.set_id.as_deref()).and_then(crate::builds::index).map_or(d.job,|i|crate::builds::DATA["items"][i]["job"].as_i64().unwrap() as i16);
            let id=Uuid::new_v4();
            sqlx::query("INSERT INTO auction_listings(id,seller,item,item_id,slot,job,quality,level,starting_price,buyout,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,clock_timestamp()+make_interval(hours=>$11))")
                .bind(id).bind(c.character_id).bind(DbJson(&item)).bind(item.id).bind(&d.slot).bind(job).bind(&item.quality).bind(item.level).bind(c.amount).bind(c.buyout).bind(c.hours).execute(&mut **tx).await.map_err(db)?;
            save(tx,c.character_id,&w).await?;Ok(Some(id))
        },
        "bid"|"buy"|"cancel"=>{
            let id=target(c)?;let r=sqlx::query("SELECT * FROM auction_listings WHERE id=$1 AND status='open' AND expires_at>clock_timestamp() FOR UPDATE").bind(id).fetch_optional(&mut **tx).await.map_err(db)?.ok_or_else(||err("AUCTION_CLOSED"))?;
            if r.get::<i64,_>("revision")!=c.revision{return Err(err("STALE_AUCTION"));}
            let seller:Uuid=r.get("seller");let bidder:Option<Uuid>=r.get("bidder");let bid:i32=r.get("bid");let buyout:i32=r.get("buyout");
            if c.action=="cancel"{
                if seller!=c.character_id{return Err(err("FORBIDDEN"));}if bidder.is_some(){return Err(err("AUCTION_HAS_BIDS"));}
                finish(tx,id,"cancelled",None,0).await?;return Ok(Some(id));
            }
            if seller==c.character_id{return Err(err("AUCTION_SELF_BUY"));}
            let price=if c.action=="buy"{buyout}else{c.amount};
            let minimum=if bidder.is_none(){r.get("starting_price")}else{bid+((i64::from(bid)*5+99)/100).max(1) as i32};
            if price<minimum&&price!=buyout||price>buyout||price<=0{return Err(err("BID_TOO_LOW"));}
            let held=if bidder==Some(c.character_id){bid}else{0};let cost=price-held;
            if w.gold<cost{return Err(err("GOLD_INSUFFICIENT"));}w.gold-=cost;
            if let Some(old)=bidder.filter(|old|*old!=c.character_id){deliver(tx,old,None,bid,"outbid_refund",id).await?;}
            sqlx::query("UPDATE auction_listings SET bidder=$2,bid=$3,revision=revision+1 WHERE id=$1").bind(id).bind(c.character_id).bind(price).execute(&mut **tx).await.map_err(db)?;
            if price==buyout{finish(tx,id,"sold",Some(c.character_id),price).await?;}
            save(tx,c.character_id,&w).await?;Ok(Some(id))
        },
        "claim"=>{
            let id=target(c)?;let r=sqlx::query("SELECT item,gold FROM economy_deliveries WHERE id=$1 AND character_id=$2 AND NOT claimed FOR UPDATE").bind(id).bind(c.character_id).fetch_optional(&mut **tx).await.map_err(db)?.ok_or_else(||err("DELIVERY_UNAVAILABLE"))?;
            let gold:i32=r.get("gold");w.gold=w.gold.checked_add(gold).ok_or_else(||err("GOLD_LIMIT"))?;
            if let Some(DbJson(value))=r.get::<Option<DbJson<Value>>,_>("item"){
                let item:loot::Item=serde_json::from_value(value).map_err(|_|err("INVALID_EQUIPMENT"))?;
                if w.loot.items.iter().chain(&w.loot.pending).any(|i|i.id==item.id){return Err(err("DUPLICATE_INSTANCE"));}
                if w.bag<60&&w.loot.items.len()<90{w.loot.items.push(item);}else if w.loot.pending.len()<20{w.loot.pending.push(item);}else{return Err(err("LOOT_STORAGE_FULL"));}
            }
            save(tx,c.character_id,&w).await?;sqlx::query("UPDATE economy_deliveries SET claimed=true WHERE id=$1").bind(id).execute(&mut **tx).await.map_err(db)?;Ok(Some(id))
        },
        _=>Err(err("INVALID_REQUEST"))
    }
}
async fn snapshot(tx:&mut Tx<'_>,c:&Command)->Result<Value,AuthError>{
    let rows=sqlx::query("SELECT l.*,s.display_name AS seller_name,(extract(epoch FROM l.expires_at)*1000)::bigint AS expires_ms FROM auction_listings l JOIN characters s ON s.id=l.seller WHERE (($1='mine' AND (l.seller=$2 OR l.bidder=$2)) OR ($1<>'mine' AND l.status='open')) AND ($3='' OR l.slot=$3) AND ($4='' OR l.quality=$4) AND ($5=-1 OR l.job IN (-1,$5)) ORDER BY l.created_at DESC,l.id LIMIT 21 OFFSET $6")
        .bind(&c.scope).bind(c.character_id).bind(&c.slot).bind(&c.quality).bind(c.job).bind(c.page*20).fetch_all(&mut **tx).await.map_err(db)?;
    let more=rows.len()>20;let listings:Vec<_>=rows.into_iter().take(20).map(|r|json!({"id":r.get::<Uuid,_>("id"),"seller":r.get::<Uuid,_>("seller"),"seller_name":r.get::<String,_>("seller_name"),"item":r.get::<DbJson<Value>,_>("item").0,"starting_price":r.get::<i32,_>("starting_price"),"buyout":r.get::<i32,_>("buyout"),"bid":r.get::<i32,_>("bid"),"bidder":r.get::<Option<Uuid>,_>("bidder"),"revision":r.get::<i64,_>("revision").to_string(),"status":r.get::<String,_>("status"),"expires_ms":r.get::<i64,_>("expires_ms")})).collect();
    let rows=sqlx::query("SELECT id,item,gold,reason,source_id FROM economy_deliveries WHERE character_id=$1 AND NOT claimed ORDER BY created_at,id LIMIT 50").bind(c.character_id).fetch_all(&mut **tx).await.map_err(db)?;
    let deliveries:Vec<_>=rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"item":r.get::<Option<DbJson<Value>>,_>("item").map(|v|v.0),"gold":r.get::<i32,_>("gold"),"reason":r.get::<String,_>("reason"),"source_id":r.get::<Uuid,_>("source_id")})).collect();
    Ok(json!({"version":1,"listings":listings,"deliveries":deliveries,"page":c.page,"more":more,"server_time_ms":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64}))
}
