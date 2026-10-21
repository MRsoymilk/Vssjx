//! Durable, allowlisted audit data. No request bodies or credentials are accepted here.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{Executor, Postgres};
use uuid::Uuid;

/// Attribute rejected HTTP attempts without retaining a body, raw path or token.
/// Both global and account budgets bound diagnostics under a valid-token flood.
pub(crate) async fn http_rejections(
    axum::extract::State(state): axum::extract::State<std::sync::Arc<crate::AppState>>,
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let bearer = crate::auth::bearer(request.headers())
        .ok()
        .map(str::to_owned);
    let route = request
        .extensions()
        .get::<axum::extract::MatchedPath>()
        .map_or("unmatched", |v| v.as_str())
        .to_owned();
    let method = match request.method().as_str() {
        "GET" => "GET",
        "POST" => "POST",
        "PUT" => "PUT",
        "PATCH" => "PATCH",
        "DELETE" => "DELETE",
        _ => "OTHER",
    };
    let correlation = request
        .extensions()
        .get::<crate::observability::RequestId>()
        .map(|v| v.0);
    let response = next.run(request).await;
    if response.status().is_client_error()
        && let (Some(auth), Some(bearer)) = (&state.auth, bearer)
        && auth.admit_http_audit(None)
        && let Ok(account) = auth.me(&bearer).await
        && auth.admit_http_audit(Some(account.id))
    {
        let code = response
            .extensions()
            .get::<crate::observability::ErrorCode>()
            .map_or("HTTP_REJECTED", |v| v.0);
        observe(auth, Event{account:Some(account.id),character:None,session:None,operation:None,action:"http.rejected",outcome:"rejected",code,details:json!({"method":method,"route":route,"status":response.status().as_u16(),"request_id":correlation})}).await;
    }
    response
}

pub(crate) struct Event<'a> {
    pub account: Option<Uuid>,
    pub character: Option<Uuid>,
    pub session: Option<Uuid>,
    pub operation: Option<Uuid>,
    pub action: &'a str,
    pub outcome: &'a str,
    pub code: &'a str,
    pub details: Value,
}
pub(crate) async fn append<'e, E: Executor<'e, Database = Postgres>>(
    executor: E,
    event: Event<'_>,
) -> Result<(), sqlx::Error> {
    // Measure PostgreSQL's actual jsonb text, including its added whitespace.
    // Keep the transaction's audit even if a growing inventory exceeds its 16KiB
    // envelope. The digest identifies the original details; attribution and the
    // operation receipt remain durable. Invalid non-object details still fail.
    let compacted = compact_details(&event.details);
    sqlx::query("INSERT INTO security_audit(account_id,character_id,session_id,operation_id,action,outcome,code,details) VALUES($1,$2,$3,$4,$5,$6,$7,CASE WHEN jsonb_typeof($8::jsonb)='object' AND octet_length($8::jsonb::text)>16384 THEN $9::jsonb ELSE $8::jsonb END)")
        .bind(event.account).bind(event.character).bind(event.session).bind(event.operation)
        .bind(event.action).bind(event.outcome).bind(event.code).bind(sqlx::types::Json(event.details))
        .bind(sqlx::types::Json(compacted))
        .execute(executor).await?;
    Ok(())
}

/// Rejected authentication and connection diagnostics are best effort; business writes use
/// append() inside their transaction and fail closed instead.
pub(crate) async fn observe(auth: &crate::auth::AuthService, event: Event<'_>) {
    if let Err(error) = append(auth.pool(), event).await {
        crate::observability::database_error(&error, "security_audit");
    }
}

pub(crate) async fn connection_event(
    auth: &crate::auth::AuthService,
    session: Uuid,
    character: Uuid,
    action: &str,
    code: &str,
    details: Value,
) {
    // Called only after join verified ownership. Character ownership is immutable;
    // it still attributes a late disconnect after login has cleaned an old session.
    let account = sqlx::query_scalar::<_, Uuid>("SELECT account_id FROM characters WHERE id=$1")
        .bind(character)
        .fetch_optional(auth.pool())
        .await
        .ok()
        .flatten();
    observe(
        auth,
        Event {
            account,
            character: Some(character),
            session: Some(session),
            operation: None,
            action,
            outcome: if code == "OK" { "observed" } else { "rejected" },
            code,
            details,
        },
    )
    .await;
}

pub(crate) fn state_summary(state: &Value) -> Value {
    json!({"character":state["character"],"potions":state["potions"],
        "equipment":state["equipment"],"shop":state["shop"].as_object().map(|s|json!({"owned":s.get("owned"),"weapon":s.get("weapon"),"armor":s.get("armor"),"slots":s.get("slots"),"quantities":s.get("quantities")})),"battle":battle_summary(&state["battle"]),"attributes":state["attributes"]["allocated"],"ai_world":state["ai_world"]})
}

fn fingerprint(value: &Value) -> Value {
    let bytes = serde_json::to_vec(value).expect("audit JSON");
    json!({"compacted":true,"json_bytes":bytes.len(),"sha256":format!("{:x}",Sha256::digest(&bytes))})
}

fn compact_details(details: &Value) -> Value {
    let mut compacted = fingerprint(details);
    // Even an unusually large inventory must retain the readable resource
    // changes alongside the digest. These are bounded, server-owned fields.
    for side in ["before", "after"] {
        if let Some(state) = details.get(side).filter(|v| v.is_object()) {
            compacted[side] = json!({
                "character":state["character"],"potions":state["potions"],
                "equipment":state["equipment"],"attributes":state["attributes"],
                "battle":state["battle"]
            });
        }
    }
    if serde_json::to_vec_pretty(&compacted).expect("audit JSON").len() <= 12_000 {
        compacted
    } else {
        fingerprint(details)
    }
}

/// Audit state changes rather than duplicating frozen templates, animation
/// events, narration and skill definitions before AND after every command.
fn battle_summary(battle: &Value) -> Value {
    if battle.is_null() {
        return Value::Null;
    }
    let mut summary = json!({
        "id":battle["id"],"revision":battle["revision"],"round":battle["round"],
        "outcome":battle["outcome"],"hp":battle["hp"],"mp":battle["mp"],
        "potions":battle["potions"],"enemy_hp":battle["enemy_hp"],
        "enemy_id":battle["enemy"]["id"],"source":fingerprint(battle)
    });
    if let Some(formation) = battle.get("formation").filter(|v| v.is_object()) {
        summary["formation"] = json!({
            "id":formation["id"],"revision":formation["revision"],"round":formation["round"],
            "outcome":formation["outcome"],
            "fighters":formation["fighters"].as_array().map(|fighters| fighters.iter().map(|f|
                json!({"id":f["id"],"hp":f["hp"],"mp":f["mp"],"potions":f["potions"]})
            ).collect::<Vec<_>>()),
            "enemies":formation["enemies"].as_array().map(|enemies| enemies.iter().map(|e|
                json!({"slot":e["slot"],"id":e["definition"]["id"],"hp":e["hp"]})
            ).collect::<Vec<_>>())
        });
    }
    summary
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn battle_audit_retains_resources_without_replay_payloads() {
        let mut battle = json!({"id":"battle","revision":"2","round":2,"outcome":"active",
            "hp":95,"mp":40,"potions":6,"enemy_hp":50,"enemy":{"id":"wolf_a"},
            "formation":{"id":"formation","revision":2,"round":2,"outcome":"active",
                "fighters":[{"id":"player","hp":95,"mp":40,"potions":6,"stats":{"large":"x".repeat(10000)}}],
                "enemies":[{"slot":"enemy:0","definition":{"id":"wolf_a"},"hp":50}],
                "events":[],"lines":vec!["战斗回放".repeat(30);30]}});
        let summary = state_summary(&json!({"battle":battle,"character":{"gold":30},"potions":6}));
        assert_eq!(summary["character"]["gold"], 30);
        assert_eq!(summary["battle"]["hp"], 95);
        assert_eq!(summary["battle"]["formation"]["fighters"][0]["mp"], 40);
        assert_eq!(summary["battle"]["formation"]["enemies"][0]["hp"], 50);
        assert!(serde_json::to_vec_pretty(&json!({"before":summary,"after":summary})).unwrap().len() < 16384);
        assert!(summary["battle"]["formation"].get("lines").is_none());
        battle["formation"]["lines"] = json!(["另一段回放"]);
        assert_ne!(summary["battle"]["source"]["sha256"], battle_summary(&battle)["source"]["sha256"]);
        assert!(state_summary(&json!({"battle":null}))["battle"].is_null());
    }

    #[tokio::test]
    #[ignore = "uses only the disposable PostgreSQL supplied by tests/run_pve_audit_bounds.py"]
    async fn audit_size_boundary() {
        let url = std::env::var("SSJX_TEST_AUDIT_DATABASE_URL").expect("owned fixture URL required");
        let pool = sqlx::PgPool::connect(&url).await.unwrap();
        let cases = [
            json!({"label":"x".repeat(16371)}), // jsonb text is exactly 16384 bytes.
            json!({"label":"x".repeat(16372)}),
            json!({"values":vec![0;6000]}), // compact JSON fits; jsonb spaces do not.
            json!({"before":{"character":{"gold":30,"hp":95},"shop":{"owned":"汉".repeat(10000)}},
                   "after":{"character":{"gold":20,"hp":95},"shop":{"owned":"汉".repeat(10000)}}}),
        ];
        for (i, details) in cases.into_iter().enumerate() {
            let bytes:i32 = sqlx::query_scalar("SELECT octet_length($1::jsonb::text)")
                .bind(sqlx::types::Json(&details)).fetch_one(&pool).await.unwrap();
            if i == 0 { assert_eq!(bytes, 16384); }
            else { assert!(bytes > 16384); }
            let operation = Uuid::new_v4();
            let mut tx = pool.begin().await.unwrap();
            append(&mut *tx, Event{account:None,character:None,session:None,operation:Some(operation),
                action:"fixture.audit_bounds",outcome:"observed",code:"OK",details:details.clone()}).await.unwrap();
            let stored:sqlx::types::Json<Value> = sqlx::query_scalar("SELECT details FROM security_audit WHERE operation_id=$1")
                .bind(operation).fetch_one(&mut *tx).await.unwrap();
            if i == 0 { assert_eq!(stored.0, details); }
            else {
                assert_eq!(stored.0["compacted"], true);
                assert_eq!(stored.0["sha256"], fingerprint(&details)["sha256"]);
                if i == 3 {
                    assert_eq!(stored.0["before"]["character"]["gold"], 30);
                    assert_eq!(stored.0["after"]["character"]["gold"], 20);
                }
            }
            tx.commit().await.unwrap();
        }
        let largest:i32 = sqlx::query_scalar("SELECT max(octet_length(details::text)) FROM security_audit WHERE action='fixture.audit_bounds'")
            .fetch_one(&pool).await.unwrap();
        assert_eq!(largest, 16384);
        let mut tx = pool.begin().await.unwrap();
        let error = append(&mut *tx, Event{account:None,character:None,session:None,operation:None,
            action:"fixture.invalid_audit",outcome:"observed",code:"OK",details:json!(["x".repeat(20000)])}).await.unwrap_err();
        assert_eq!(error.as_database_error().unwrap().code().as_deref(), Some("23514"));
        tx.rollback().await.unwrap();
        pool.close().await;
    }
}
