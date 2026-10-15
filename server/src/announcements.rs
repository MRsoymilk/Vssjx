//! One bounded, expiring operator announcement shared by every game connection.
use crate::observability::now_ms;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::Mutex,
    time::{Duration, Instant},
};
use uuid::Uuid;

#[derive(Clone, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct AnnouncementDraft {
    pub request_id: Uuid,
    pub text: String,
    pub duration_seconds: u64,
}
struct Active {
    draft: AnnouncementDraft,
    deadline: Instant,
    expires_at_ms: u64,
}
#[derive(Default)]
struct State {
    revision: u64,
    active: Option<Active>,
    retired: VecDeque<Uuid>,
}
pub struct Announcements {
    epoch: Uuid,
    pub(crate) csrf_token: Uuid,
    state: Mutex<State>,
}
impl Default for Announcements {
    fn default() -> Self {
        Self {
            epoch: Uuid::new_v4(),
            csrf_token: Uuid::new_v4(),
            state: Mutex::new(State::default()),
        }
    }
}
impl Announcements {
    pub fn publish(
        &self,
        mut draft: AnnouncementDraft,
        now: Instant,
    ) -> Result<Value, &'static str> {
        if draft.request_id.is_nil() || !(10..=86400).contains(&draft.duration_seconds)
            || draft.text.len() > 960 || draft.text.chars().count() > 240
            || draft.text.chars().any(|c| (c.is_control() && !matches!(c, '\n' | '\r' | '\t'))
                || matches!(c, '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2060}'..='\u{206f}' | '\u{feff}')) {
            return Err("INVALID_ANNOUNCEMENT");
        }
        draft.text = draft.text.split_whitespace().collect::<Vec<_>>().join(" ");
        if draft.text.is_empty() {
            return Err("INVALID_ANNOUNCEMENT");
        }
        let mut state = self.state.lock().expect("announcements");
        Self::expire(&mut state, now);
        if state.retired.contains(&draft.request_id) {
            return Err("ANNOUNCEMENT_SUPERSEDED");
        }
        if let Some(active) = &state.active
            && active.draft.request_id == draft.request_id
        {
            return if active.draft == draft {
                Ok(self.packet(&state, now))
            } else {
                Err("ANNOUNCEMENT_ID_CONFLICT")
            };
        }
        state.revision += 1;
        Self::retire(&mut state);
        state.active = Some(Active {
            deadline: now + Duration::from_secs(draft.duration_seconds),
            expires_at_ms: now_ms() + draft.duration_seconds * 1000,
            draft,
        });
        Ok(self.packet(&state, now))
    }
    pub fn cancel(&self, id: Uuid, now: Instant) -> Result<Value, &'static str> {
        let mut state = self.state.lock().expect("announcements");
        Self::expire(&mut state, now);
        if let Some(active) = &state.active {
            if active.draft.request_id != id {
                return Err("ANNOUNCEMENT_REPLACED");
            }
            Self::retire(&mut state);
            state.revision += 1;
        }
        Ok(self.packet(&state, now))
    }
    pub fn packet_since(&self, revision: Option<u64>, now: Instant) -> Option<(u64, Value)> {
        let mut state = self.state.lock().expect("announcements");
        Self::expire(&mut state, now);
        (revision != Some(state.revision)).then(|| (state.revision, self.packet(&state, now)))
    }
    fn expire(state: &mut State, now: Instant) {
        if state
            .active
            .as_ref()
            .is_some_and(|active| now >= active.deadline)
        {
            Self::retire(state);
            state.revision += 1;
        }
    }
    fn retire(state: &mut State) {
        if let Some(active) = state.active.take() {
            state.retired.push_back(active.draft.request_id);
            while state.retired.len() > 64 {
                state.retired.pop_front();
            }
        }
    }
    fn packet(&self, state: &State, now: Instant) -> Value {
        let notice = state.active.as_ref().map(|active| json!({"id":active.draft.request_id,
            "text":active.draft.text,"remaining_ms":active.deadline.saturating_duration_since(now).as_millis().max(1) as u64,
            "expires_at_ms":active.expires_at_ms.to_string()}));
        json!({"type":"announcement.state","epoch":self.epoch,"revision":state.revision.to_string(),"notice":notice})
    }
}
