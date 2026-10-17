//! Complete original icon catalog; gameplay names and values are reconstructed.
use serde::Deserialize;
use serde_json::{Value,json};
use sha2::{Digest,Sha256};
use std::{collections::BTreeMap,sync::LazyLock};
pub const SLOTS: [&str;10] = ["weapon","pendant","armor","wrist","belt","pants","boots","ring","necklace","hat"];
const DATA: &str = include_str!("../../client/assets/data/shop-v2.json");
#[derive(Deserialize)]
pub struct Item {
    pub id:String, pub name:String, pub slot:String, pub price:i32,
    pub attack:i32, pub defense:i32, pub visual:i32, pub head_visual:i32,
    pub job:i16, pub restore_hp:i32, pub restore_mp:i32,
}
impl Item { pub fn equipment(&self)->bool {SLOTS.contains(&self.slot.as_str())} }
static CATALOG: LazyLock<Value> = LazyLock::new(||serde_json::from_str(DATA).expect("fixed catalog"));
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
