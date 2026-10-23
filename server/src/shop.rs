//! Complete original icon catalog; gameplay names and values are reconstructed.
use serde::Deserialize;
use serde_json::{Value,json};
use sha2::{Digest,Sha256};
use std::{collections::BTreeMap,sync::LazyLock};
pub const SLOTS: [&str;10] = ["weapon","pendant","armor","wrist","belt","pants","boots","ring","necklace","hat"];
const DATA: &str = include_str!("../../client/assets/data/shop-v2.json");
#[derive(Clone,Copy,Default,Deserialize,PartialEq,Eq,Debug)]
#[serde(rename_all="snake_case")]
pub enum ItemEffect {
    #[default]
    None,
    ResetAttributes,
    Teleport,
}
#[derive(Deserialize)]
pub struct Item {
    pub id:String, pub name:String, pub slot:String, pub price:i32,
    pub attack:i32, pub defense:i32, pub visual:i32, pub head_visual:i32,
    pub job:i16, pub restore_hp:i32, pub restore_mp:i32,
    #[serde(default="any_gender")]
    pub gender:i16,
    #[serde(default)]
    pub effect:ItemEffect,
    #[serde(default)]
    pub capacity:i32,
}
fn any_gender()->i16{-1}
impl Item {
    pub fn equipment(&self)->bool {SLOTS.contains(&self.slot.as_str())}
    pub fn unique(&self)->bool {self.equipment()||self.slot=="gourd"}
    pub fn equip_error(&self,job:i16,gender:i16)->Option<&'static str>{
        if self.job>=0&&self.job!=job{return Some("WRONG_JOB");}
        if self.gender>=0&&self.gender!=gender{return Some("WRONG_GENDER");}
        None
    }
}
static CATALOG: LazyLock<Value> = LazyLock::new(||serde_json::from_str(DATA).expect("fixed catalog"));
static LEGACY: LazyLock<Value> = LazyLock::new(||serde_json::from_str(include_str!("../../client/assets/data/shop-v1.json")).expect("legacy catalog"));
pub static ITEMS: LazyLock<Vec<Item>> = LazyLock::new(||serde_json::from_value(CATALOG["items"].clone()).expect("typed catalog"));
static HASH: LazyLock<String> = LazyLock::new(||format!("{:x}",Sha256::digest(DATA.replace("\r\n","\n").as_bytes())));
pub fn item(id:&str)->Option<&'static Item>{ITEMS.iter().find(|i|i.id==id)}
pub fn equipped<'a>(gear:&'a BTreeMap<String,bool>,slot:&str)->Option<&'a str>{gear.iter().find(|(id,on)|**on&&item(id).is_some_and(|i|i.slot==slot)).map(|(id,_)|id.as_str())}
pub fn bonus(gear:&BTreeMap<String,bool>)->(i32,i32){gear.iter().filter(|(_,on)|**on).filter_map(|(id,_)|item(id)).fold((0,0),|(a,d),i|(a+i.attack,d+i.defense))}
pub fn view(gear:&BTreeMap<String,bool>,quantities:&BTreeMap<String,i32>,potions:i32)->Value {
    let slots:BTreeMap<_,_> = SLOTS.into_iter().map(|s|(s,equipped(gear,s))).collect();
    let mut quantities=quantities.clone();quantities.insert("potion".into(),potions);
    json!({"version":"shop-v2","catalog_sha256":*HASH,"owned":gear.keys().collect::<Vec<_>>(),"quantities":quantities,"slots":slots,"weapon":equipped(gear,"weapon"),"armor":equipped(gear,"armor")})
}
pub fn appearance(gear:&BTreeMap<String,bool>)->[i32;3]{
    [equipped(gear,"weapon").and_then(item).map_or(0,|i|i.visual),
     equipped(gear,"armor").and_then(item).map_or(0,|i|i.visual),
     equipped(gear,"hat").and_then(item).map_or(0,|i|i.head_visual)]
}

/// Adapt only the wire response; stored receipts and authoritative state stay v2.
/// Existing APKs know six IDs and reject unknown ownership or a v2 envelope.
pub fn client_packet(mut packet:Value,version:u32)->Value {
    if version>=2{return packet;}
    if let Some(shop)=packet["state"].get_mut("shop") {
        let legacy=&*LEGACY;
        let known=|id:&Value|legacy["items"].as_array().expect("items").iter().any(|item|item["id"]==*id);
        let owned:Vec<_>=shop["owned"].as_array().expect("owned").iter().filter(|id|known(id)).cloned().collect();
        let weapon=if known(&shop["weapon"]){shop["weapon"].clone()}else{Value::Null};
        let armor=if known(&shop["armor"]){shop["armor"].clone()}else{Value::Null};
        *shop=json!({"version":"shop-v1","catalog":legacy["items"],"owned":owned,"weapon":weapon,"armor":armor});
    }
    packet
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn boneglow_sets_use_authoritative_slots_codes_and_role_restrictions(){
        let stems=["mzs","wzs","mck","wck","mfs","wfs"];
        for (index,stem) in stems.iter().enumerate(){
            let job=(index/2) as i16;
            let gender=(index%2) as i16;
            let mut gear=BTreeMap::new();
            for slot in SLOTS {
                let id=format!("ai/boneglow/{stem}/{slot}");
                let entry=item(&id).expect("every slot exists");
                assert_eq!(entry.slot,slot);
                assert!(entry.equipment());
                assert_eq!(entry.equip_error(job,gender),None);
                assert_eq!(entry.equip_error(job,1-gender),Some("WRONG_GENDER"));
                assert_eq!(entry.equip_error((job+1)%3,gender),Some("WRONG_JOB"));
                gear.insert(id,true);
            }
            assert_eq!(appearance(&gear),[28+index as i32,12+index as i32,10+index as i32]);
            assert_eq!(bonus(&gear),(12,27));
            let quantities=gear.keys().map(|id|(id.clone(),1)).collect();
            let view=view(&gear,&quantities,6);
            assert_eq!(view["slots"].as_object().unwrap().len(),10);
            assert_eq!(view["owned"].as_array().unwrap().len(),10);
        }
        assert_eq!(item("original/if1").unwrap().gender,-1);
        assert!(item("ai/boneglow/fake/weapon").is_none());
    }
    #[test]
    fn gravebloom_sets_coexist_with_boneglow_and_mix_independent_slots(){
        let stems=["mzs","wzs","mck","wck","mfs","wfs"];
        for (index,stem) in stems.iter().enumerate(){
            let mut gear=BTreeMap::new();
            for slot in SLOTS {
                let id=format!("ai/gravebloom/{stem}/{slot}");
                let entry=item(&id).unwrap();
                assert_eq!(entry.equip_error((index/2) as i16,(index%2) as i16),None);
                assert_eq!(entry.equip_error((index/2) as i16,1-(index%2) as i16),Some("WRONG_GENDER"));
                assert_eq!(entry.equip_error(((index/2+1)%3) as i16,(index%2) as i16),Some("WRONG_JOB"));
                gear.insert(id,true);
            }
            assert_eq!(appearance(&gear),[34+index as i32,18+index as i32,16+index as i32]);
            assert_eq!(bonus(&gear),(14,27));
            gear.insert(format!("ai/gravebloom/{stem}/hat"),false);
            gear.insert(format!("ai/boneglow/{stem}/hat"),true);
            assert_eq!(appearance(&gear),[34+index as i32,18+index as i32,10+index as i32]);
        }
        assert_eq!(ITEMS.len(),459);
    }
    #[test]
    fn eva01_sets_preserve_role_restrictions_and_mix_with_previous_families(){
        for (index,stem) in ["mzs","wzs","mck","wck","mfs","wfs"].iter().enumerate(){
            let mut gear=BTreeMap::new();
            for slot in SLOTS {
                let id=format!("ai/eva01/{stem}/{slot}");
                let entry=item(&id).expect("every EVA slot is catalogued");
                assert_eq!(entry.slot,slot);
                assert_eq!(entry.equip_error((index/2) as i16,(index%2) as i16),None);
                assert_eq!(entry.equip_error((index/2) as i16,1-(index%2) as i16),Some("WRONG_GENDER"));
                assert_eq!(entry.equip_error(((index/2+1)%3) as i16,(index%2) as i16),Some("WRONG_JOB"));
                gear.insert(id,true);
            }
            assert_eq!(appearance(&gear),[40+index as i32,24+index as i32,22+index as i32]);
            assert_eq!(bonus(&gear),(14,27));
            gear.insert(format!("ai/eva01/{stem}/hat"),false);
            gear.insert(format!("ai/gravebloom/{stem}/hat"),true);
            assert_eq!(appearance(&gear),[40+index as i32,24+index as i32,16+index as i32]);
        }
        assert!(item("ai/eva01/unknown/weapon").is_none());
    }
    #[test]
    fn vow_sets_preserve_roles_and_mix_all_three_visual_slots(){
        for (index,stem) in ["mzs","wzs","mck","wck","mfs","wfs"].iter().enumerate(){
            let mut gear=BTreeMap::new();
            for slot in SLOTS {
                let id=format!("ai/vow/{stem}/{slot}");
                let entry=item(&id).expect("every ceremonial slot is catalogued");
                assert_eq!(entry.slot,slot);
                assert_eq!(entry.price,if slot=="weapon" {140} else {70});
                assert_eq!(entry.equip_error((index/2) as i16,(index%2) as i16),None);
                assert_eq!(entry.equip_error((index/2) as i16,1-(index%2) as i16),Some("WRONG_GENDER"));
                assert_eq!(entry.equip_error(((index/2+1)%3) as i16,(index%2) as i16),Some("WRONG_JOB"));
                gear.insert(id,true);
            }
            let n=index as i32;
            assert_eq!(appearance(&gear),[47+n,30+n,28+n]);
            assert_eq!(bonus(&gear),(14,27));
            for (slot,expected) in [("hat",[47+n,30+n,22+n]),("armor",[47+n,24+n,22+n]),("weapon",[40+n,24+n,22+n])] {
                gear.insert(format!("ai/vow/{stem}/{slot}"),false);
                gear.insert(format!("ai/eva01/{stem}/{slot}"),true);
                assert_eq!(appearance(&gear),expected);
            }
        }
        assert!(item("ai/vow/unknown/weapon").is_none());
    }
    #[test]
    fn potian_axe_is_one_authoritative_weapon_for_both_lishi_genders(){
        let id="ai/legendary/potian_axe";
        let entry=item(id).expect("approved axe is catalogued");
        assert_eq!(ITEMS.iter().filter(|i|i.id==id).count(),1);
        assert_eq!((entry.slot.as_str(),entry.price,entry.attack,entry.visual),("weapon",250,20,46));
        for gender in [0,1] {
            assert_eq!(entry.equip_error(0,gender),None);
            for job in [1,2] {assert_eq!(entry.equip_error(job,gender),Some("WRONG_JOB"));}
        }
        let gear=BTreeMap::from([(id.into(),true),("ai/boneglow/wzs/armor".into(),true),("ai/gravebloom/wzs/hat".into(),true)]);
        assert_eq!(appearance(&gear),[46,13,17]);
        assert_eq!(bonus(&gear),(20,6));
        assert_eq!(view(&gear,&BTreeMap::new(),0)["weapon"],id);
    }
    #[test]
    fn original_named_rebirth_pill_is_a_typed_consumable(){
        let entry=item("restored/rebirth_pill").unwrap();
        assert_eq!(entry.name,"重生再造丹");
        assert_eq!(entry.slot,"consumable");
        assert_eq!(entry.price,200);
        assert_eq!(entry.effect,ItemEffect::ResetAttributes);
        assert_eq!((entry.restore_hp,entry.restore_mp),(0,0));
        assert!(!entry.equipment());
        assert_eq!(item("potion").unwrap().effect,ItemEffect::None);
    }
    #[test]
    fn travel_talisman_is_a_typed_consumable_without_healing(){
        let entry=item("restored/shenxing_scroll").unwrap();
        assert_eq!((entry.name.as_str(),entry.price),("神行符",30));
        assert_eq!(entry.effect,ItemEffect::Teleport);
        assert_eq!(entry.slot,"consumable");
        assert_eq!((entry.restore_hp,entry.restore_mp),(0,0));
        assert!(!entry.equipment());
    }
    #[test]
    fn legacy_wire_response_never_rewrites_full_receipt_or_exposes_unknown_items(){
        let gear:BTreeMap<String,bool>=BTreeMap::from([("sword".into(),false),("weapon_2".into(),true),("original/if1".into(),true)]);
        let quantities=gear.keys().map(|id|(id.clone(),1)).collect();
        let full=json!({"type":"pve.result","state":{"shop":view(&gear,&quantities,6)}});
        let old=client_packet(full.clone(),1);
        assert_eq!(old["state"]["shop"]["version"],"shop-v1");
        assert_eq!(old["state"]["shop"]["catalog"].as_array().unwrap().len(),6);
        assert_eq!(old["state"]["shop"]["owned"],json!(["sword","weapon_2"]));
        assert_eq!(old["state"]["shop"]["weapon"],"weapon_2");
        assert_eq!(client_packet(full.clone(),2),full);
        assert!(full["state"]["shop"]["owned"].as_array().unwrap().contains(&json!("original/if1")));
    }
}
