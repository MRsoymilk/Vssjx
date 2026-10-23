//! Personal gathering. The caller owns character lock, receipt, audit and commit.
use crate::{characters::Character,pve::Context,pve_rules::{Action,Command}};
use rand::Rng;
use serde_json::{Value,json};
use sqlx::{Postgres,Row,Transaction,types::Json};
use uuid::Uuid;
#[derive(serde::Deserialize)]
struct Frozen { map_id:String,material:String,quantity:i32,respawn_ms:i64,duration_ms:i64 }

pub fn is_action(action:Action)->bool{matches!(action,Action::GatherStart|Action::GatherFinish|Action::GatherCancel|Action::GatherDiscard)}
pub fn material_name(id:&str)->&str{match id{"iron"=>"铁矿","copper"=>"铜矿","gancao"=>"甘草","danggui"=>"当归",_=>"未知材料"}}
pub async fn view(tx:&mut Transaction<'_,Postgres>,character:Uuid,map:&str)->Result<Value,sqlx::Error>{
    let value:Json<Value>=sqlx::query_scalar(r#"SELECT jsonb_build_object(
        'version','gathering-v1','stack_limit',999,
        'materials',COALESCE((SELECT jsonb_object_agg(material,quantity) FROM gathering_materials WHERE character_id=$1),'{}'::jsonb),
        'nodes',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',n.id,'map_id',n.map_id,'cell',jsonb_build_array(n.cell_x,n.cell_y),'material',n.material,'duration_ms',n.duration_ms,'respawn_ms',n.respawn_ms,'min_quantity',n.min_quantity,'max_quantity',n.max_quantity,'available_at_ms',COALESCE(c.available_at_ms,0)) ORDER BY n.id) FROM (SELECT * FROM gathering_nodes WHERE map_id=$2 AND enabled ORDER BY id LIMIT 16) n LEFT JOIN gathering_cooldowns c ON c.node_id=n.id AND c.character_id=$1),'[]'::jsonb),
        'active',(SELECT jsonb_build_object('token',g.token,'node_id',g.node_id,'map_id',g.snapshot->>'map_id','material',g.snapshot->>'material','duration_ms',g.snapshot->'duration_ms','ready_at_ms',g.ready_at_ms,'expires_at_ms',g.expires_at_ms,'owner_epoch',g.owner_epoch::text,'connection_epoch',g.connection_epoch::text,'position_revision',g.position_revision::text,'revision',g.character_revision::text,'cell',jsonb_build_array(g.cell_x,g.cell_y)) FROM gathering_active g JOIN characters ch ON ch.id=g.character_id AND ch.state_revision=g.character_revision WHERE g.character_id=$1))"#)
        .bind(character).bind(map).fetch_one(&mut **tx).await?;
    Ok(value.0)
}
pub async fn cancel(tx:&mut Transaction<'_,Postgres>,character:Uuid)->Result<(),sqlx::Error>{
    sqlx::query("DELETE FROM gathering_active WHERE character_id=$1").bind(character).execute(&mut **tx).await?;Ok(())
}
pub async fn apply(tx:&mut Transaction<'_,Postgres>,c:&Character,ctx:&Context,command:&Command,busy:bool)->Result<Result<Vec<String>,&'static str>,sqlx::Error>{
    let now:i64=sqlx::query_scalar("SELECT (extract(epoch FROM clock_timestamp())*1000)::bigint").fetch_one(&mut **tx).await?;
    if (command.quantity.is_some()&&command.action!=Action::GatherDiscard)||command.attributes.is_some()||command.battle_id.is_some()||command.enemy_slot.is_some()||command.encounter_version.is_some(){return Ok(Err("INVALID_GATHER_COMMAND"));}
    if command.action==Action::GatherCancel {
        let target=command.target.as_deref().and_then(|s|Uuid::parse_str(s).ok());
        if target.is_none(){return Ok(Err("INVALID_GATHER_COMMAND"));}
        sqlx::query("DELETE FROM gathering_active WHERE character_id=$1 AND token=$2").bind(c.id).bind(target).execute(&mut **tx).await?;
        return Ok(Ok(vec!["已停止采集，未消耗资源。".into()]));
    }
    if c.corpse.is_some(){return Ok(Err("SOUL_STATE"));}
    if busy||ctx.duel_active{return Ok(Err("BATTLE_ACTIVE"));}
    if ctx.map_id!=c.map_id||ctx.moving{return Ok(Err("GATHER_INTERRUPTED"));}
    if command.expected_revision.as_deref()!=Some(&c.state_revision){return Ok(Err("STALE_GATHERING"));}
    if command.action==Action::GatherDiscard {
        let material=command.target.as_deref().unwrap_or("");let quantity=command.quantity.unwrap_or(1);
        if !["iron","copper","gancao","danggui"].contains(&material)||!(1..=999).contains(&quantity){return Ok(Err("INVALID_GATHER_COMMAND"));}
        let current:Option<i32>=sqlx::query_scalar("SELECT quantity FROM gathering_materials WHERE character_id=$1 AND material=$2 FOR UPDATE").bind(c.id).bind(material).fetch_optional(&mut **tx).await?;
        if current.is_none_or(|v|v<quantity){return Ok(Err("MATERIALS_INSUFFICIENT"));}
        if current==Some(quantity){sqlx::query("DELETE FROM gathering_materials WHERE character_id=$1 AND material=$2").bind(c.id).bind(material).execute(&mut **tx).await?;}
        else {sqlx::query("UPDATE gathering_materials SET quantity=quantity-$3 WHERE character_id=$1 AND material=$2").bind(c.id).bind(material).bind(quantity).execute(&mut **tx).await?;}
        cancel(tx,c.id).await?;return Ok(Ok(vec![format!("已丢弃{} ×{}。",material_name(material),quantity)]));
    }
    if command.action==Action::GatherStart {
        let active:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM gathering_active WHERE character_id=$1 AND owner_epoch=$2 AND connection_epoch=$3 AND position_revision=$4 AND character_revision=$5 AND expires_at_ms>$6)")
            .bind(c.id).bind(ctx.owner).bind(ctx.connection_epoch as i64).bind(ctx.position_revision as i64).bind(c.state_revision.parse::<i64>().unwrap()).bind(now).fetch_one(&mut **tx).await?;
        if active{return Ok(Err("GATHER_BUSY"));}
        let row=sqlx::query("SELECT * FROM gathering_nodes WHERE id=$1 AND map_id=$2 AND enabled FOR SHARE")
            .bind(command.target.as_deref().unwrap_or("")).bind(&ctx.map_id).fetch_optional(&mut **tx).await?;
        let Some(row)=row else{return Ok(Err("GATHER_NOT_FOUND"));};
        let cell=[row.get::<i32,_>("cell_x"),row.get::<i32,_>("cell_y")];
        let map=crate::world_map::WorldMap::load(&ctx.map_id);
        if map.as_ref().is_none_or(|m|!m.walkable(cell)) {return Ok(Err("GATHER_NOT_FOUND"));}
        if (cell[0]-ctx.cell[0]).abs()+(cell[1]-ctx.cell[1]).abs()>1{return Ok(Err("GATHER_TOO_FAR"));}
        let cooldown:Option<i64>=sqlx::query_scalar("SELECT available_at_ms FROM gathering_cooldowns WHERE character_id=$1 AND node_id=$2").bind(c.id).bind(row.get::<String,_>("id")).fetch_optional(&mut **tx).await?;
        if cooldown.is_some_and(|t|t>now){return Ok(Err("GATHER_COOLDOWN"));}
        let material:String=row.get("material");let maximum:i32=row.get("max_quantity");
        let current:i32=sqlx::query_scalar("SELECT COALESCE((SELECT quantity FROM gathering_materials WHERE character_id=$1 AND material=$2),0)").bind(c.id).bind(&material).fetch_one(&mut **tx).await?;
        if current+maximum>999{return Ok(Err("MATERIAL_BAG_FULL"));}
        let duration:i64=row.get("duration_ms");let respawn:i64=row.get("respawn_ms");
        let snapshot=json!({"map_id":ctx.map_id,"material":material,"quantity":rand::thread_rng().gen_range(row.get::<i32,_>("min_quantity")..=maximum),"respawn_ms":respawn,"duration_ms":duration});
        sqlx::query("INSERT INTO gathering_active(character_id,token,node_id,snapshot,ready_at_ms,expires_at_ms,owner_epoch,connection_epoch,position_revision,character_revision,cell_x,cell_y) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT(character_id) DO UPDATE SET token=EXCLUDED.token,node_id=EXCLUDED.node_id,snapshot=EXCLUDED.snapshot,ready_at_ms=EXCLUDED.ready_at_ms,expires_at_ms=EXCLUDED.expires_at_ms,owner_epoch=EXCLUDED.owner_epoch,connection_epoch=EXCLUDED.connection_epoch,position_revision=EXCLUDED.position_revision,character_revision=EXCLUDED.character_revision,cell_x=EXCLUDED.cell_x,cell_y=EXCLUDED.cell_y")
            .bind(c.id).bind(Uuid::new_v4()).bind(row.get::<String,_>("id")).bind(Json(snapshot)).bind(now+duration).bind(now+duration+30000).bind(ctx.owner).bind(ctx.connection_epoch as i64).bind(ctx.position_revision as i64).bind(c.state_revision.parse::<i64>().unwrap()+1).bind(ctx.cell[0]).bind(ctx.cell[1]).execute(&mut **tx).await?;
        return Ok(Ok(vec![format!("开始采集{}，移动、战斗或断线将中断。",material_name(&material))]));
    }
    let row=sqlx::query("SELECT * FROM gathering_active WHERE character_id=$1 FOR UPDATE").bind(c.id).fetch_optional(&mut **tx).await?;
    let Some(row)=row else{return Ok(Err("GATHER_INTERRUPTED"));};
    let token:Uuid=row.get("token");let Ok(snapshot)=serde_json::from_value::<Frozen>(row.get::<Json<Value>,_>("snapshot").0) else{return Ok(Err("INVALID_GATHER_STATE"));};
    if !["iron","copper","gancao","danggui"].contains(&snapshot.material.as_str())||!(1..=10).contains(&snapshot.quantity)||!(1000..=86400000).contains(&snapshot.respawn_ms)||!(1000..=60000).contains(&snapshot.duration_ms){return Ok(Err("INVALID_GATHER_STATE"));}
    if command.target.as_deref()!=Some(token.to_string().as_str())||row.get::<i64,_>("owner_epoch")!=ctx.owner||row.get::<i64,_>("connection_epoch")!=ctx.connection_epoch as i64||row.get::<i64,_>("position_revision")!=ctx.position_revision as i64||row.get::<i64,_>("character_revision").to_string()!=c.state_revision||row.get::<i32,_>("cell_x")!=ctx.cell[0]||row.get::<i32,_>("cell_y")!=ctx.cell[1]||snapshot.map_id!=ctx.map_id||now>row.get::<i64,_>("expires_at_ms"){return Ok(Err("GATHER_INTERRUPTED"));}
    if now<row.get::<i64,_>("ready_at_ms"){return Ok(Err("GATHER_NOT_READY"));}
    let material=snapshot.material.as_str();let quantity=snapshot.quantity;
    let changed=sqlx::query("INSERT INTO gathering_materials(character_id,material,quantity) VALUES($1,$2,$3) ON CONFLICT(character_id,material) DO UPDATE SET quantity=gathering_materials.quantity+EXCLUDED.quantity WHERE gathering_materials.quantity+EXCLUDED.quantity<=999")
        .bind(c.id).bind(material).bind(quantity).execute(&mut **tx).await?.rows_affected();
    if changed==0{return Ok(Err("MATERIAL_BAG_FULL"));}
    sqlx::query("INSERT INTO gathering_cooldowns(character_id,node_id,available_at_ms) VALUES($1,$2,$3) ON CONFLICT(character_id,node_id) DO UPDATE SET available_at_ms=EXCLUDED.available_at_ms")
        .bind(c.id).bind(row.get::<String,_>("node_id")).bind(now+snapshot.respawn_ms).execute(&mut **tx).await?;
    cancel(tx,c.id).await?;
    Ok(Ok(vec![format!("获得{} ×{}，已放入材料袋。",material_name(material),quantity)]))
}
