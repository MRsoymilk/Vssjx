//! Durable, allowlisted audit data. No request bodies or credentials are accepted here.
use serde_json::{Value, json};
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
    sqlx::query("INSERT INTO security_audit(account_id,character_id,session_id,operation_id,action,outcome,code,details) VALUES($1,$2,$3,$4,$5,$6,$7,$8)")
        .bind(event.account).bind(event.character).bind(event.session).bind(event.operation)
        .bind(event.action).bind(event.outcome).bind(event.code).bind(sqlx::types::Json(event.details))
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
        "equipment":state["equipment"],"shop":state["shop"].as_object().map(|s|json!({"owned":s.get("owned"),"weapon":s.get("weapon"),"armor":s.get("armor")})),"battle":state["battle"],"attributes":state["attributes"]["allocated"]})
}
