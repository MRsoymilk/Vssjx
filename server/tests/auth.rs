use vssjx_server::auth::{canonical_username, validate_password};

#[test]
fn usernames_are_canonical_and_not_character_nicknames() {
    assert_eq!(canonical_username("  Player_123 ").unwrap(), "player_123");
    for name in [
        "a",
        "姓名",
        "hello-world",
        "abc\nuser",
        "abc@example.com",
        &"a".repeat(33),
    ] {
        assert!(canonical_username(name).is_err());
    }
}

#[test]
fn passwords_have_bounded_cost_and_preserve_whitespace() {
    assert!(validate_password(" longer password ").is_ok());
    assert!(validate_password("12字中文密码内容很长没有限制符号").is_ok());
    assert!(validate_password("short").is_err());
    assert!(validate_password(&" ".repeat(12)).is_err());
    assert!(validate_password(&"x".repeat(129)).is_err());
}
