//! Durable daily unique in-game accounts, only exposed on the local monitor.
use crate::{AppState, auth::{self, AuthError}};
use axum::{Json, extract::{Query, State}, http::StatusCode};
use serde::Deserialize;
use serde_json::{Value, json};
use sqlx::{PgPool, types::Json as DbJson};
use std::{sync::Arc, time::{Duration, Instant}};
use uuid::Uuid;

// China has no DST; keeping the day key explicit also makes rollover testable.
pub(crate) fn beijing_day(time_ms: u64) -> i32 {
    ((time_ms / 1000 + 8 * 3600) / 86400) as i32
}

pub(crate) async fn record(pool: &PgPool, character: Uuid, day: i32) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO daily_online_accounts(day,account_id) SELECT DATE '1970-01-01'+$2::int,account_id FROM characters WHERE id=$1 ON CONFLICT DO NOTHING")
        .bind(character).bind(day).execute(pool).await?;
    Ok(())
}

#[derive(Default)]
pub(crate) struct Presence {
    day: Option<i32>,
    attempted: Option<Instant>,
}
impl Presence {
    fn due(&self, time_ms: u64, now: Instant) -> Option<i32> {
        let day=beijing_day(time_ms);
        if self.day==Some(day) || (self.day.is_none() && self.attempted.is_some_and(|t|now.saturating_duration_since(t)<Duration::from_secs(30))) {
            None
        } else { Some(day) }
    }
    fn completed(&mut self, day: i32, now: Instant, ok: bool) {
        self.attempted=Some(now);
        self.day=ok.then_some(day);
    }
    pub(crate) async fn record_if_due(&mut self, pool: &PgPool, character: Uuid) {
        let now=Instant::now();
        let Some(day)=self.due(crate::observability::now_ms(),now) else { return };
        let result=record(pool,character,day).await;
        self.completed(day,now,result.is_ok());
        if let Err(error)=result { crate::observability::database_error(&error,"daily_online_record"); }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct DailyQuery {
    #[serde(default = "default_days")]
    days: i32,
}
fn default_days() -> i32 { 30 }

pub(crate) async fn daily(
    State(state): State<Arc<AppState>>,
    Query(query): Query<DailyQuery>,
) -> Result<Json<Value>, AuthError> {
    if ![7,30,90].contains(&query.days) {
        return Err(AuthError(StatusCode::BAD_REQUEST,"INVALID_REQUEST"));
    }
    let auth = auth::service(&state)?;
    let rows = sqlx::query_scalar::<_,DbJson<Value>>(r#"
        WITH bounds AS (
            SELECT (clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date AS today,
                   (started_at AT TIME ZONE 'Asia/Shanghai')::date AS started
            FROM online_stats_metadata WHERE singleton
        ), days AS (
            SELECT today-n AS day,today,started FROM bounds,generate_series(0,$1::int-1) n
        ), counts AS (
            SELECT day,count(*) AS users FROM daily_online_accounts
            WHERE day BETWEEN (SELECT today FROM bounds)-($1::int-1) AND (SELECT today FROM bounds)
            GROUP BY day
        )
        SELECT jsonb_build_object('date',d.day::text,
            'users',CASE WHEN d.day>=d.started THEN COALESCE(c.users,0) ELSE c.users END,
            'coverage',CASE WHEN d.day<d.started THEN 'historical' WHEN d.day=d.today OR d.day=d.started THEN 'partial' ELSE 'complete' END)
        FROM days d LEFT JOIN counts c USING(day) ORDER BY d.day
    "#).bind(query.days).fetch_all(auth.pool()).await.map_err(|error| {
        crate::observability::database_error(&error,"daily_online_stats");
        AuthError(StatusCode::SERVICE_UNAVAILABLE,"DATABASE_UNAVAILABLE")
    })?;
    Ok(Json(json!({"timezone":"Asia/Shanghai","metric":"unique_online_accounts","days":rows.into_iter().map(|v|v.0).collect::<Vec<_>>()})))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn beijing_midnight_is_not_utc_midnight() {
        assert_eq!(beijing_day(57_599_999),0);
        assert_eq!(beijing_day(57_600_000),1);
        assert_eq!(beijing_day(86_400_000),1);
        assert_eq!(beijing_day(144_000_000),2);
    }
    #[test]
    fn idle_connection_rolls_over_without_repeated_writes() {
        let now=Instant::now();
        let mut presence=Presence::default();
        assert_eq!(presence.due(57_599_999,now),Some(0));
        presence.completed(0,now,true);
        assert_eq!(presence.due(57_599_999,now),None);
        // Midnight must not wait 30 seconds after a successful previous-day write.
        assert_eq!(presence.due(57_600_000,now),Some(1));
        presence.completed(1,now,true);
        assert_eq!(presence.due(86_400_000,now),None);
    }
    #[test]
    fn failures_retry_boundedly_instead_of_locking_gameplay() {
        let now=Instant::now();
        let mut presence=Presence::default();
        presence.completed(0,now,false);
        assert_eq!(presence.due(57_599_999,now+Duration::from_secs(29)),None);
        assert_eq!(presence.due(57_600_000,now+Duration::from_secs(30)),Some(1));
    }
}
