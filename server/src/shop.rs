//! Fixed, reconstructed catalog shared with the client; never accept prices/stats.
use serde::Deserialize;
use serde_json::{Value, json};
use std::{collections::BTreeMap, sync::LazyLock};

#[derive(Deserialize)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub slot: String,
    pub price: i32,
    pub attack: i32,
    pub defense: i32,
    pub visual: i32,
}
static CATALOG: LazyLock<Value> = LazyLock::new(|| serde_json::from_str(include_str!("../../client/assets/data/shop-v1.json")).expect("fixed shop catalog"));
pub static ITEMS: LazyLock<Vec<Item>> = LazyLock::new(|| serde_json::from_value(CATALOG["items"].clone()).expect("typed catalog"));
pub fn item(id: &str) -> Option<&'static Item> { ITEMS.iter().find(|i| i.id == id) }
pub fn equipped<'a>(gear: &'a BTreeMap<String,bool>, slot: &str) -> Option<&'a str> {
    gear.iter().find(|(id,on)| **on && item(id).is_some_and(|i| i.slot == slot)).map(|(id,_)|id.as_str())
}
pub fn bonus(gear: &BTreeMap<String,bool>) -> (i32,i32) {
    gear.iter().filter(|(_,on)|**on).filter_map(|(id,_)|item(id)).fold((0,0), |(a,d),i|(a+i.attack,d+i.defense))
}
pub fn view(gear: &BTreeMap<String,bool>) -> Value {
    json!({"version":"shop-v1","catalog":CATALOG["items"],"owned":gear.keys().collect::<Vec<_>>(),"weapon":equipped(gear,"weapon"),"armor":equipped(gear,"armor")})
}
pub fn appearance(gear: &BTreeMap<String,bool>) -> [i32;2] {
    ["weapon","armor"].map(|s| equipped(gear,s).and_then(item).map_or(0,|i|i.visual))
}
