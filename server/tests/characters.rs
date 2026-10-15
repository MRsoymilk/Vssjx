use serde_json::Value;
use vssjx_server::characters::canonical_name;

#[test]
fn nickname_contract_matches_fixed_cross_language_vectors() {
    let vectors: Value =
        serde_json::from_str(include_str!("../../shared/protocol/nickname-v1.json")).unwrap();
    for sample in vectors["valid"].as_array().unwrap() {
        let (display, key) = canonical_name(sample["raw"].as_str().unwrap()).unwrap();
        assert_eq!(display, sample["display_name"]);
        assert_eq!(key, sample["name_key"]);
    }
    for raw in vectors["invalid"].as_array().unwrap() {
        assert!(
            canonical_name(raw.as_str().unwrap()).is_err(),
            "accepted {raw}"
        );
    }
}

#[test]
fn create_fields_are_strict_and_authoritative_values_cannot_be_supplied() {
    use vssjx_server::characters::CreateCharacter;
    let request = serde_json::json!({"operation_id": uuid::Uuid::new_v4(), "display_name":"青衫客", "job":0,"gender":1,"school":2,"rules_version":"creation-v1"});
    assert!(serde_json::from_value::<CreateCharacter>(request.clone()).is_ok());
    for field in ["account_id", "gold", "hp", "name_key", "state_revision"] {
        let mut forged = request.clone();
        forged[field] = serde_json::json!(123);
        assert!(serde_json::from_value::<CreateCharacter>(forged).is_err());
    }
    let duplicate = format!(
        "{{\"operation_id\":\"{}\",\"display_name\":\"青衫\",\"display_name\":\"其他\",\"job\":0,\"gender\":1,\"school\":2,\"rules_version\":\"creation-v1\"}}",
        uuid::Uuid::new_v4()
    );
    assert!(serde_json::from_str::<CreateCharacter>(&duplicate).is_err());
}
