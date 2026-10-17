//! Single-process world coordinator. Map motion never waits for database/network IO.
//! One owned CharacterActor record per character; socket replacement is epoch-fenced.
use crate::{
    AppState,
    auth::{self, AuthError, AuthService, Peer},
    chat::{ChatConfig, ChatHub, ChatResult},
    observability::{Observability, RequestId},
    world_map::{Motion, WorldMap, config_hash},
    world_replication::{Publication, Publisher, SYNC_VERSION},
};
use axum::{
    Json,
    extract::{
        Extension, State, WebSocketUpgrade,
        rejection::JsonRejection,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode},
    response::Response,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::sync::atomic::Ordering;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::{Mutex as AsyncMutex, Semaphore};
use tracing::Instrument;
use uuid::Uuid;

#[derive(Clone, Copy)]
pub struct WorldConfig {
    pub max_players: usize,
    pub save_seconds: u64,
    pub grace_seconds: u64,
    pub chat: ChatConfig,
}
impl Default for WorldConfig {
    fn default() -> Self {
        Self {
            max_players: 1000,
            save_seconds: 10,
            grace_seconds: 15,
            chat: ChatConfig::default(),
        }
    }
}

#[derive(Clone, Serialize, PartialEq, Eq)]
pub struct Entity {
    pub net_id: u32,
    pub id: Uuid,
    pub display_name: String,
    pub job: i16,
    pub gender: i16,
    pub cell: [i32; 2],
    pub next_cell: Option<[i32; 2]>,
    pub segment_progress: u16,
    pub entity_revision: String,
    pub last_input_seq: String,
    pub world_epoch: String,
}
struct CharacterActor {
    business: Arc<AsyncMutex<()>>,
    in_battle: bool,
    map_id: String,
    net_id: u32,
    id: Uuid,
    session: Uuid,
    game: Uuid,
    chat_start_seq: u64,
    epoch: u64,
    owner: i64,
    display_name: String,
    job: i16,
    gender: i16,
    motion: Motion,
    last_input: u64,
    last_command: Instant,
    connected: bool,
    disconnected_at: Option<Instant>,
}
impl CharacterActor {
    fn public(&self) -> Entity {
        Entity {
            net_id: self.net_id,
            id: self.id,
            display_name: self.display_name.clone(),
            job: self.job,
            gender: self.gender,
            cell: self.motion.cell,
            next_cell: self.motion.next,
            segment_progress: (self.motion.progress * 1000.0).round() as u16,
            entity_revision: self.motion.revision.to_string(),
            last_input_seq: self.last_input.to_string(),
            world_epoch: self.owner.to_string(),
        }
    }
}
struct StateData {
    actors: HashMap<Uuid, CharacterActor>,
    revision: u64,
    chat: ChatHub,
    next_net_id: u32,
    population: crate::population::Population,
    ruins_population: crate::population::Population,
}
pub struct WorldHub {
    metrics: Arc<Observability>,
    data: Mutex<StateData>,
    admissions: AsyncMutex<()>,
    map: WorldMap,
    ruins: WorldMap,
    config: WorldConfig,
    pub sockets: Arc<Semaphore>,
    publications: Publisher,
    ruins_publications: Publisher,
}
#[derive(Clone)]
struct Ownership {
    business: Arc<AsyncMutex<()>>,
    id: Uuid,
    session: Uuid,
    game: Uuid,
    chat_start_seq: u64,
    epoch: u64,
    owner: i64,
    joined_revision: u64,
    map_id: String,
}
#[derive(Clone)]
struct SavedPosition {
    id: Uuid,
    owner: i64,
    revision: i64,
    cell: [i32; 2],
    map_id: String,
}
impl WorldHub {
    pub fn new(config: WorldConfig) -> Arc<Self> {
        Self::with_metrics(config, Arc::new(Observability::default()))
    }
    pub fn with_metrics(config: WorldConfig, metrics: Arc<Observability>) -> Arc<Self> {
        let hub = Arc::new(Self {
            metrics,
            data: Mutex::new(StateData {
                actors: HashMap::new(),
                revision: 0,
                chat: ChatHub::new(config.chat),
                next_net_id: 1,
                population: crate::population::Population::new(&WorldMap::default()),
                ruins_population: crate::population::Population::new(&WorldMap::load("ancient_ruins").expect("ruins")),
            }),
            admissions: AsyncMutex::new(()),
            map: WorldMap::default(),
            ruins: WorldMap::load("ancient_ruins").expect("ruins"),
            config,
            sockets: Arc::new(Semaphore::new(config.max_players + 64)),
            publications: Publisher::default(),
            ruins_publications: Publisher::default(),
        });
        let weak = Arc::downgrade(&hub);
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(Duration::from_millis(100));
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
            let mut last = Instant::now();
            loop {
                ticker.tick().await;
                let Some(hub) = weak.upgrade() else { break };
                let now = Instant::now();
                let dt = now.duration_since(last).as_secs_f64();
                last = now;
                let (revision, mut entities, mut ruins_entities) = {
                    let mut state = hub.data.lock().expect("world state");
                    let mut changed = false;
                    for actor in state.actors.values_mut() {
                        if actor.connected && !actor.in_battle {
                            changed |= actor.motion.advance(dt);
                        }
                    }
                    if changed {
                        state.revision += 1;
                    }
                    state.chat.drain(now);
                    state.population.advance(&hub.map, dt);
                    state.ruins_population.advance(&hub.ruins, dt);
                    let entities: Vec<_> = state
                        .actors
                        .values()
                        .filter(|a| a.connected && a.map_id == "qingyun_trail")
                        .map(CharacterActor::public)
                        .collect();
                    let ruins_entities = state.actors.values().filter(|a| a.connected && a.map_id == "ancient_ruins").map(CharacterActor::public).collect::<Vec<_>>();
                    (state.revision, entities, ruins_entities)
                };
                // No world-state lock is held while sorting/encoding for network IO.
                entities.sort_unstable_by_key(|e| e.net_id);
                ruins_entities.sort_unstable_by_key(|e| e.net_id);
                let bytes = hub.publications.publish(revision, entities) + hub.ruins_publications.publish(revision, ruins_entities);
                hub.metrics.record_tick(
                    (dt * 1_000_000.0) as u64,
                    now.elapsed().as_micros() as u64,
                    bytes,
                );
            }
        });
        hub
    }
    fn map_for(&self, id: &str) -> &WorldMap {
        if id == "ancient_ruins" { &self.ruins } else { &self.map }
    }
    fn publisher_for(&self, id: &str) -> &Publisher {
        if id == "ancient_ruins" { &self.ruins_publications } else { &self.publications }
    }
    pub(crate) fn monitor_snapshot(&self) -> Value {
        let (connected, retained, moving, chat) = {
            let state = self.data.lock().expect("world state");
            (
                state.actors.values().filter(|a| a.connected).count(),
                state.actors.len(),
                state
                    .actors
                    .values()
                    .filter(|a| {
                        a.connected && (a.motion.next.is_some() || !a.motion.route.is_empty())
                    })
                    .count(),
                state.chat.monitor_snapshot(),
            )
        };
        json!({"map_id":"qingyun_trail","maps":["qingyun_trail","ancient_ruins"],"max_players":self.config.max_players,"connected_players":connected,"retained_players":retained,"moving_players":moving,
            "world_seq":self.publications.sequence().to_string(),"last_tick_age_ms":crate::observability::now_ms().saturating_sub(self.metrics.last_tick_ms.load(Ordering::Relaxed)),"chat":chat})
    }
    fn position(actor: &CharacterActor) -> SavedPosition {
        SavedPosition {
            id: actor.id,
            owner: actor.owner,
            revision: actor.motion.revision as i64,
            cell: actor.motion.cell,
            map_id: actor.map_id.clone(),
        }
    }
    fn owned(actor: &CharacterActor, owner: &Ownership) -> bool {
        actor.session == owner.session && actor.epoch == owner.epoch && actor.connected
    }
    fn save_snapshot(&self, owner: &Ownership) -> Option<SavedPosition> {
        let state = self.data.lock().ok()?;
        let actor = state.actors.get(&owner.id)?;
        Self::owned(actor, owner).then(|| Self::position(actor))
    }
    fn current(&self, owner: &Ownership) -> bool {
        self.data
            .lock()
            .expect("world state")
            .actors
            .get(&owner.id)
            .is_some_and(|actor| Self::owned(actor, owner))
    }
    async fn persist(auth: &AuthService, p: SavedPosition) -> Result<(), AuthError> {
        sqlx::query("UPDATE characters SET cell_x=$1,cell_y=$2,position_revision=$3 WHERE id=$4 AND owner_epoch=$5 AND position_revision<=$3 AND map_id=$6")
            .bind(p.cell[0]).bind(p.cell[1]).bind(p.revision).bind(p.id).bind(p.owner).bind(p.map_id).execute(auth.pool()).await.map_err(db_error)?;
        Ok(())
    }
    async fn join(
        &self,
        auth: &AuthService,
        id: Uuid,
        session: Uuid,
        maps_version: u32,
    ) -> Result<Ownership, AuthError> {
        let _gate = self.admissions.lock().await;
        let business = self.data.lock().expect("world state").actors.get(&id).map(|a| a.business.clone()).unwrap_or_else(|| Arc::new(AsyncMutex::new(())));
        let _business = business.lock().await;
        // Persist retired ownership before permitting a new login session to load it.
        let retired: Vec<SavedPosition> = {
            let state = self.data.lock().expect("world state");
            state
                .actors
                .values()
                .filter(|a| {
                    !a.connected
                        && a.disconnected_at.is_some_and(|t| {
                            t.elapsed() >= Duration::from_secs(self.config.grace_seconds)
                        })
                })
                .map(Self::position)
                .collect()
        };
        for p in retired {
            Self::persist(auth, p.clone()).await?;
            self.data.lock().expect("world state").actors.remove(&p.id);
        }
        if !auth.live_session(session).await? {
            return Err(error(401, "SESSION_REVOKED"));
        }
        {
            let mut state = self.data.lock().expect("world state");
            if let Some(actor) = state.actors.get_mut(&id) {
                if actor.session != session {
                    return Err(error(409, "CHARACTER_BUSY"));
                }
                if actor.map_id != "qingyun_trail" && maps_version != 1 { return Err(error(409,"MAP_UPDATE_REQUIRED")); }
                actor.epoch += 1;
                actor.connected = true;
                actor.disconnected_at = None;
                actor.last_input = 0;
                actor.last_command = Instant::now() - Duration::from_secs(1);
                actor.motion.stop();
                let owner = Ownership {
                    business: business.clone(),
                    id,
                    session,
                    game: actor.game,
                    chat_start_seq: actor.chat_start_seq,
                    epoch: actor.epoch,
                    owner: actor.owner,
                    map_id: actor.map_id.clone(),
                    joined_revision: state.revision + 1,
                };
                state.revision += 1;
                return Ok(owner);
            }
            if state.actors.len() >= self.config.max_players {
                return Err(error(503, "WORLD_FULL"));
            }
        }
        let row=sqlx::query("UPDATE characters c SET owner_epoch=owner_epoch+1,position_revision=0 WHERE c.id=$1 AND map_id IN ('qingyun_trail','ancient_ruins') AND ($3 OR map_id='qingyun_trail') AND owner_epoch<9223372036854775807 AND EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.id=$2 AND s.account_id=c.account_id AND NOT a.disabled AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp()) RETURNING display_name,job,gender,cell_x,cell_y,owner_epoch,active_battle_id,map_id")
            .bind(id).bind(session).bind(maps_version == 1).fetch_optional(auth.pool()).await.map_err(db_error)?.ok_or(error(403,"WORLD_UNAVAILABLE"))?;
        let cell = [row.get("cell_x"), row.get("cell_y")];
        let map_id: String = row.get("map_id");
        if !self.map_for(&map_id).walkable(cell) {
            return Err(error(409, "INVALID_SAVED_POSITION"));
        }
        let mut state = self.data.lock().expect("world state");
        let owner = Ownership {
            business: business.clone(),
            id,
            session,
            game: Uuid::new_v4(),
            chat_start_seq: state.chat.latest(),
            epoch: 1,
            owner: row.get("owner_epoch"),
            joined_revision: 0,
            map_id: map_id.clone(),
        };
        let net_id = state.next_net_id;
        state.next_net_id = net_id
            .checked_add(1)
            .ok_or(error(503, "WORLD_ID_EXHAUSTED"))?;
        let actor = CharacterActor {
            business: business.clone(),
            in_battle: row.get::<Option<Uuid>,_>("active_battle_id").is_some(),
            map_id,
            net_id,
            id,
            session,
            game: owner.game,
            chat_start_seq: owner.chat_start_seq,
            epoch: 1,
            owner: owner.owner,
            display_name: row.get("display_name"),
            job: row.get("job"),
            gender: row.get("gender"),
            motion: Motion::new(cell),
            last_input: 0,
            last_command: Instant::now() - Duration::from_secs(1),
            connected: true,
            disconnected_at: None,
        };
        state.actors.insert(id, actor);
        state.revision += 1;
        Ok(Ownership {
            joined_revision: state.revision,
            ..owner
        })
    }
    fn command(&self, owner: &Ownership, input: &ClientMessage) -> Result<(), AuthError> {
        let mut state = self.data.lock().expect("world state");
        let actor = state
            .actors
            .get_mut(&owner.id)
            .ok_or(error(401, "SESSION_REPLACED"))?;
        if !Self::owned(actor, owner) {
            return Err(error(401, "SESSION_REPLACED"));
        }
        let (game, epoch, world, input_seq, target) = match input {
            ClientMessage::MoveTo {
                game_session_id,
                connection_epoch,
                world_epoch,
                input_seq,
                target,
            } => (
                game_session_id,
                connection_epoch,
                world_epoch,
                input_seq,
                Some(*target),
            ),
            ClientMessage::Stop {
                game_session_id,
                connection_epoch,
                world_epoch,
                input_seq,
            } => (
                game_session_id,
                connection_epoch,
                world_epoch,
                input_seq,
                None,
            ),
            _ => return Err(error(400, "INVALID_MESSAGE")),
        };
        if *game != owner.game
            || decimal(epoch)? != owner.epoch
            || decimal(world)? != owner.owner as u64
        {
            return Err(error(409, "STALE_CONNECTION"));
        }
        let sequence = decimal(input_seq)?;
        if sequence <= actor.last_input {
            return Err(error(409, "STALE_INPUT"));
        }
        if actor.last_command.elapsed() < Duration::from_millis(80) {
            return Err(error(429, "RATE_LIMITED"));
        }
        if actor.in_battle { return Err(error(409,"BATTLE_ACTIVE")); }
        actor.last_command = Instant::now();
        actor.last_input = sequence;
        if let Some(goal) = target {
            if !actor.motion.move_to(self.map_for(&actor.map_id), goal) {
                return Err(error(422, "INVALID_TARGET"));
            }
        } else {
            actor.motion.stop();
        }
        state.revision += 1;
        Ok(())
    }
    fn chat(
        &self,
        owner: &Ownership,
        id: Uuid,
        channel: &str,
        text: &str,
        muted: bool,
    ) -> Result<ChatResult, AuthError> {
        let mut state = self.data.lock().expect("world state");
        let actor = state
            .actors
            .get(&owner.id)
            .filter(|a| Self::owned(a, owner))
            .ok_or(error(401, "SESSION_REPLACED"))?;
        let name = actor.display_name.clone();
        Ok(state
            .chat
            .submit((owner.id, &name), id, channel, text, muted, Instant::now()))
    }
    fn pve_context(&self, owner: &Ownership, target: Option<&str>) -> Result<crate::pve::Context,AuthError> {
        let state = self.data.lock().expect("world state");
        let actor = state.actors.get(&owner.id).filter(|a|Self::owned(a,owner)).ok_or(error(401,"SESSION_REPLACED"))?;
        Ok(crate::pve::Context { character: owner.id,session:owner.session,owner:owner.owner,cell:actor.motion.cell,
            moving: actor.motion.next.is_some() || !actor.motion.route.is_empty(),
            target_cell:target.and_then(|id| if actor.map_id == "ancient_ruins" { state.ruins_population.get(id) } else { state.population.get(id) }).map(|r|r.motion.cell),
            map_id: actor.map_id.clone(), position_revision: actor.motion.revision })
    }
    fn pve_applied(&self, owner: &Ownership, result: &Value) {
        let mut state = self.data.lock().expect("world state");
        if let Some(actor)=state.actors.get_mut(&owner.id).filter(|a|Self::owned(a,owner)) {
            let character = &result["state"]["character"];
            if let Some(map_id) = character["map_id"].as_str() && actor.map_id != map_id {
                let revision = actor.motion.revision + 1;
                actor.map_id = map_id.to_owned();
                actor.motion = Motion::new([character["cell_x"].as_i64().expect("cell") as i32, character["cell_y"].as_i64().expect("cell") as i32]);
                actor.motion.revision = revision;
                actor.epoch += 1;
                actor.connected = false;
                actor.disconnected_at = Some(Instant::now());
                state.revision += 1;
                return;
            }
            actor.in_battle = result["state"]["battle"]["outcome"] == "active";
            if actor.in_battle { actor.motion.stop(); }
        }
    }
    async fn disconnect(&self, auth: &AuthService, owner: &Ownership, leave: bool) {
        let _gate = self.admissions.lock().await;
        let _business = owner.business.lock().await;
        let position = {
            let mut state = self.data.lock().expect("world state");
            let Some(actor) = state.actors.get_mut(&owner.id) else {
                return;
            };
            if !Self::owned(actor, owner) {
                return;
            }
            actor.connected = false;
            actor.disconnected_at = Some(Instant::now());
            actor.motion.stop();
            actor.motion.next = None;
            actor.motion.progress = 0.0;
            let p = Self::position(actor);
            state.revision += 1;
            p
        };
        if Self::persist(auth, position).await.is_ok() && leave {
            self.data
                .lock()
                .expect("world state")
                .actors
                .remove(&owner.id);
        }
    }
}
fn error(status: u16, code: &'static str) -> AuthError {
    AuthError(StatusCode::from_u16(status).expect("status"), code)
}
fn db_error(cause: sqlx::Error) -> AuthError {
    crate::observability::database_error(&cause, "world");
    error(503, "DATABASE_UNAVAILABLE")
}
pub fn decimal(raw: &str) -> Result<u64, AuthError> {
    if raw.is_empty()
        || raw.len() > 19
        || (raw.len() > 1 && raw.starts_with('0'))
        || !raw.bytes().all(|c| c.is_ascii_digit())
    {
        return Err(error(400, "INVALID_SEQUENCE"));
    }
    let value = raw
        .parse::<u64>()
        .map_err(|_| error(400, "INVALID_SEQUENCE"))?;
    if value > i64::MAX as u64 {
        return Err(error(400, "INVALID_SEQUENCE"));
    }
    Ok(value)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TicketRequest {
    character_id: Uuid,
    protocol_version: u32,
    config_hash: String,
}
pub(crate) async fn ticket(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
    payload: Result<Json<TicketRequest>, JsonRejection>,
) -> Result<Json<Value>, AuthError> {
    let auth = auth::service(&state)?;
    auth.admit(auth::peer_ip(peer), None)?;
    let bearer = auth::bearer(&headers)?;
    let account = auth.me(bearer).await?;
    let Json(request) = payload.map_err(|_| error(400, "INVALID_REQUEST"))?;
    if request.protocol_version != 1 {
        return Err(error(409, "PROTOCOL_MISMATCH"));
    }
    if request.config_hash != config_hash() {
        return Err(error(409, "CONFIG_MISMATCH"));
    }
    let raw = auth::token();
    let mut tx = auth.pool().begin().await.map_err(db_error)?;
    let session:Option<Uuid>=sqlx::query_scalar("SELECT s.id FROM sessions s JOIN characters c ON c.account_id=s.account_id WHERE s.access_digest=$1 AND c.id=$2 AND c.account_id=$3 AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp() FOR UPDATE OF s")
        .bind(auth::token_digest(bearer)?).bind(request.character_id).bind(account.id).fetch_optional(&mut *tx).await.map_err(db_error)?;
    let session = session.ok_or(error(403, "FORBIDDEN"))?;
    sqlx::query("DELETE FROM world_tickets WHERE expires_at<=NOW()")
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    sqlx::query("INSERT INTO world_tickets (digest,session_id,character_id,expires_at) VALUES ($1,$2,$3,NOW()+INTERVAL '20 seconds') ON CONFLICT(session_id) DO UPDATE SET digest=EXCLUDED.digest,character_id=EXCLUDED.character_id,expires_at=EXCLUDED.expires_at")
        .bind(auth::token_digest(&raw)?).bind(session).bind(request.character_id).execute(&mut *tx).await.map_err(db_error)?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(
        json!({"ticket":raw,"expires_in":20,"character_id":request.character_id,"config_hash":config_hash(),"announcement_version":1,"population_version":1,"pve_version":1,"maps_version":1}),
    ))
}
#[derive(Deserialize)]
#[serde(tag = "type", deny_unknown_fields)]
pub enum ClientMessage {
    #[serde(rename = "auth.exchange")]
    Exchange {
        ticket: String,
        protocol_version: u32,
        config_hash: String,
        #[serde(default)]
        world_sync_version: u32,
        #[serde(default)]
        announcement_version: u32,
        #[serde(default)]
        population_version: u32,
        #[serde(default)]
        pve_version: u32,
        #[serde(default)]
        maps_version: u32,
    },
    #[serde(rename = "world.move_to")]
    MoveTo {
        game_session_id: Uuid,
        connection_epoch: String,
        world_epoch: String,
        input_seq: String,
        target: [i32; 2],
    },
    #[serde(rename = "world.stop")]
    Stop {
        game_session_id: Uuid,
        connection_epoch: String,
        world_epoch: String,
        input_seq: String,
    },
    #[serde(rename = "pve.command")]
    Pve { command: crate::pve_rules::Command },
    #[serde(rename = "ping")]
    Ping {},
    #[serde(rename = "world.leave")]
    Leave {},
    #[serde(rename = "chat.send")]
    ChatSend {
        client_message_id: Uuid,
        channel: String,
        text: String,
    },
}
struct ObservedSocket {
    inner: WebSocket,
    metrics: Arc<Observability>,
    id: Uuid,
}
impl ObservedSocket {
    async fn recv(&mut self) -> Option<Result<Message, axum::Error>> {
        let message = self.inner.recv().await;
        if matches!(message, Some(Err(_))) {
            self.metrics
                .event("websocket", "WORLD_RECEIVE_FAILED", self.id);
            // Tungstenite's raw error may contain peer-supplied protocol data.
            tracing::warn!(code = "WORLD_RECEIVE_FAILED", "world socket receive failed");
        }
        message
    }
    async fn send(&mut self, message: Message) -> Result<(), ()> {
        let bytes = match &message {
            Message::Text(text) => text.len(),
            Message::Binary(bytes) => bytes.len(),
            _ => 0,
        };
        let result = tokio::time::timeout(Duration::from_secs(2), self.inner.send(message)).await;
        if matches!(result, Ok(Ok(()))) {
            self.metrics
                .ws_sent_bytes
                .fetch_add(bytes as u64, Ordering::Relaxed);
            Ok(())
        } else {
            self.metrics
                .ws_send_failures
                .fetch_add(1, Ordering::Relaxed);
            self.metrics
                .event("websocket", "WORLD_SEND_FAILED", self.id);
            tracing::warn!("world socket send failed or timed out");
            Err(())
        }
    }
}
async fn send(socket: &mut ObservedSocket, value: Value) -> Result<(), ()> {
    send_raw(socket, value.to_string()).await
}
async fn send_raw(socket: &mut ObservedSocket, text: String) -> Result<(), ()> {
    socket.send(Message::Text(text.into())).await
}
async fn send_delta(socket: &mut ObservedSocket, publication: &Publication) -> Result<(), ()> {
    socket
        .send(Message::Binary(publication.delta.clone()))
        .await
}
async fn fail(socket: &mut ObservedSocket, code: &'static str) {
    socket.metrics.event("websocket", code, socket.id);
    tracing::warn!(code, "world operation rejected");
    let _ = send(socket, json!({"type":"error","code":code})).await;
}
pub(crate) async fn upgrade(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    Extension(request_id): Extension<RequestId>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Result<Response, AuthError> {
    if !state.config.web_origins.allows(&headers) {
        return Err(error(403, "ORIGIN_NOT_ALLOWED"));
    }
    let auth = auth::service(&state)?;
    auth.admit(auth::peer_ip(peer), None)?;
    let hub = state.world.clone().ok_or(error(503, "AUTH_UNAVAILABLE"))?;
    let permit = hub
        .sockets
        .clone()
        .try_acquire_owned()
        .map_err(|_| error(503, "SERVER_BUSY"))?;
    let auth = auth.clone();
    let announcements = state.announcements.clone();
    Ok(ws
        .max_message_size(2048)
        .max_frame_size(2048)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            let connection_id = Uuid::new_v4();
            let span =
                tracing::error_span!("world_socket", %connection_id, request_id=%request_id.0);
            connection(socket, auth, hub, announcements, connection_id)
                .instrument(span)
                .await;
        }))
}
async fn connection(socket: WebSocket, auth: AuthService, hub: Arc<WorldHub>, announcements: Arc<crate::announcements::Announcements>, id: Uuid) {
    let _connection = hub.metrics.socket(id);
    let mut socket = ObservedSocket {
        inner: socket,
        metrics: hub.metrics.clone(),
        id,
    };
    let handshake = tokio::time::timeout(Duration::from_secs(5), socket.recv()).await;
    let Ok(Some(Ok(Message::Text(text)))) = handshake else {
        socket
            .metrics
            .event("websocket", "HANDSHAKE_TIMEOUT_OR_CLOSED", id);
        tracing::warn!(
            code = "HANDSHAKE_TIMEOUT_OR_CLOSED",
            "world handshake not completed"
        );
        return;
    };
    let Ok(ClientMessage::Exchange {
        ticket,
        protocol_version,
        config_hash: hash,
        world_sync_version,
        announcement_version,
        population_version,
        pve_version,
        maps_version,
    }) = serde_json::from_str::<ClientMessage>(&text)
    else {
        fail(&mut socket, "INVALID_HANDSHAKE").await;
        return;
    };
    if protocol_version != 1 || hash != config_hash() {
        fail(&mut socket, "CONFIG_MISMATCH").await;
        return;
    }
    if world_sync_version != SYNC_VERSION {
        fail(&mut socket, "WORLD_PROTOCOL_MISMATCH").await;
        return;
    }
    let Ok(digest) = auth::token_digest(&ticket) else {
        fail(&mut socket, "INVALID_TICKET").await;
        return;
    };
    let consumed=sqlx::query("DELETE FROM world_tickets WHERE digest=$1 AND expires_at>clock_timestamp() RETURNING session_id,character_id").bind(digest).fetch_optional(auth.pool()).await;
    let row = match consumed {
        Ok(Some(row)) => row,
        Ok(None) => {
            fail(&mut socket, "INVALID_TICKET").await;
            return;
        }
        Err(error) => {
            crate::observability::database_error(&error, "world_ticket_exchange");
            fail(&mut socket, "DATABASE_UNAVAILABLE").await;
            return;
        }
    };
    let owner = match hub
        .join(&auth, row.get("character_id"), row.get("session_id"), maps_version)
        .await
    {
        Ok(o) => o,
        Err(e) => {
            fail(&mut socket, e.1).await;
            return;
        }
    };
    let stream = Uuid::new_v4();
    tracing::info!(
        connection_epoch = owner.epoch,
        "world connection authenticated"
    );
    let (mut baseline, mut updates) = hub.publisher_for(&owner.map_id).subscribe();
    let synchronized = tokio::time::timeout(Duration::from_secs(5), async {
        while baseline.source_revision < owner.joined_revision
            || !baseline.entities.iter().any(|e| e.id == owner.id)
        {
            baseline = updates.recv().await.map_err(|_| ())?;
        }
        Ok::<_, ()>(())
    })
    .await;
    if !matches!(synchronized, Ok(Ok(()))) {
        socket
            .metrics
            .event("websocket", "WORLD_BASELINE_TIMEOUT", id);
        tracing::warn!(
            code = "WORLD_BASELINE_TIMEOUT",
            "world baseline unavailable"
        );
        hub.disconnect(&auth, &owner, false).await;
        return;
    }
    let ready = json!({"type":"auth.ready","character_id":owner.id,"game_session_id":owner.game,"connection_epoch":owner.epoch.to_string(),"world_epoch":owner.owner.to_string(),"stream_id":stream,"world_stream_id":baseline.epoch,"world_sync_version":SYNC_VERSION,"config_hash":config_hash(),"map_id":owner.map_id,"map_hash":hub.map_for(&owner.map_id).hash(),"instance_id":"main","tick_ms":100});
    if send(&mut socket, ready).await.is_err() {
        hub.disconnect(&auth, &owner, false).await;
        return;
    }
    let (chat_ready, mut chat_cursor) = {
        let state = hub.data.lock().expect("world state");
        state.chat.ready_since(owner.chat_start_seq)
    };
    if send(&mut socket, chat_ready).await.is_err() {
        hub.disconnect(&auth, &owner, false).await;
        return;
    }
    if send_snapshot(&mut socket, stream, &baseline).await.is_err() {
        hub.disconnect(&auth, &owner, false).await;
        return;
    }
    if pve_version == 1 {
        let result = {
            let _business = owner.business.lock().await;
            match hub.pve_context(&owner,None) {
                Ok(context) => crate::pve::snapshot(&auth,&context).await.inspect(|value|hub.pve_applied(&owner,value)),
                Err(e) => Err(e),
            }
        };
        match result {
            Ok(value) => { if send(&mut socket,value).await.is_err(){ hub.disconnect(&auth,&owner,false).await;return; } },
            Err(e) => { fail(&mut socket,e.1).await;hub.disconnect(&auth,&owner,false).await;return; }
        }
    }
    let mut chat_pending: Option<Uuid> = None;
    let mut announcement_revision = None;
    let mut population_revision = None;
    let mut pulse = tokio::time::interval(Duration::from_millis(100));
    pulse.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut checked = Instant::now();
    let mut saved = Instant::now();
    let mut heard = Instant::now();
    let mut window = Instant::now();
    let mut messages = 0;
    let mut leave = false;
    crate::security::connection_event(&auth,owner.session,owner.id,"world.join","OK",json!({"map_id":owner.map_id,"connection_id":id})).await;
    let mut audit_since = Instant::now();
    let mut move_accepted = 0_u32;
    let mut move_rejected = 0_u32;
    let mut last_move_code = "OK";
    loop {
        tokio::select! {
            publication=updates.recv()=>{
                if !hub.current(&owner){fail(&mut socket,"SESSION_REPLACED").await;break;}
                let publication=match publication {Ok(p)=>p,Err(_)=>{fail(&mut socket,"WORLD_STREAM_LAGGED").await;break;}};
                if send_delta(&mut socket,&publication).await.is_err(){break;}
            },
            message=socket.recv()=>{
                let Some(Ok(Message::Text(text)))=message else{break};
                if window.elapsed()>=Duration::from_secs(1){window=Instant::now();messages=0;}
                messages+=1;if messages>20{crate::security::connection_event(&auth,owner.session,owner.id,"world.protocol","RATE_LIMITED",json!({"connection_id":id})).await;fail(&mut socket,"RATE_LIMITED").await;break;}
                heard=Instant::now();
                let input=match serde_json::from_str::<ClientMessage>(&text){Ok(v)=>v,Err(_)=>{crate::security::connection_event(&auth,owner.session,owner.id,"world.protocol","INVALID_MESSAGE",json!({"connection_id":id})).await;fail(&mut socket,"INVALID_MESSAGE").await;break}};
                if !hub.current(&owner){fail(&mut socket,"SESSION_REPLACED").await;break;}
                if matches!(input,ClientMessage::Leave {}){leave=true;break;}
                match auth.live_session(owner.session).await {Ok(true)=>{},Ok(false)=>{fail(&mut socket,"SESSION_REVOKED").await;leave=true;break},Err(_)=>{fail(&mut socket,"DATABASE_UNAVAILABLE").await;break}}
                if matches!(input,ClientMessage::Ping {}){if send(&mut socket,json!({"type":"pong"})).await.is_err(){break;}}
                else if let ClientMessage::Pve{command}=&input {
                    if pve_version != 1 { fail(&mut socket,"PVE_UNSUPPORTED").await;break; }
                    if command.action == crate::pve_rules::Action::Transfer && maps_version != 1 { fail(&mut socket,"MAP_UPDATE_REQUIRED").await; continue; }
                    let result = {
                        let _business = owner.business.lock().await;
                        match hub.pve_context(&owner,command.target.as_deref()) {
                            Ok(context) => match crate::pve::execute(&auth,&context,command).await {
                                Ok(value) => match crate::pve::snapshot(&auth,&context).await {
                                    Ok(current) => {hub.pve_applied(&owner,&current);Ok(value)},
                                    Err(e) => Err(e),
                                },
                                Err(e) => Err(e),
                            },
                            Err(e) => Err(e),
                        }
                    };
                    match result {
                        Ok(value)=>{
                            if send(&mut socket,value).await.is_err(){break;}
                            if !hub.current(&owner) { break; }
                        },
                        Err(e)=>{if e.1!="GAMEPLAY_RATE_LIMITED" {crate::security::connection_event(&auth,owner.session,owner.id,"pve.refused",e.1,json!({"connection_id":id})).await;}fail(&mut socket,e.1).await;break;}
                    }
                }
                else if let ClientMessage::ChatSend{client_message_id,channel,text}=&input {
                    let muted=match auth.chat_muted(owner.session).await{Ok(value)=>value,Err(e)=>{fail(&mut socket,e.1).await;break;}};
                    match hub.chat(&owner,*client_message_id,channel,text,muted) {
                        Ok(result)=>{
                            if result.status=="QUEUED" {chat_pending=Some(*client_message_id);}
                            if send(&mut socket,json!({"type":"chat.result","result":result})).await.is_err(){break;}
                        },
                        Err(e)=>{fail(&mut socket,e.1).await;break;}
                    }
                }
                else {match hub.command(&owner,&input) { Ok(())=>{move_accepted+=1;},Err(e)=>{move_rejected+=1;last_move_code=e.1;fail(&mut socket,e.1).await;} }}
            },
            _=pulse.tick()=>{
                if !hub.current(&owner){fail(&mut socket,"SESSION_REPLACED").await;break;}
                if population_version == 1 {
                    let packet = { let state = hub.data.lock().expect("world state");
                        if owner.map_id == "ancient_ruins" { state.ruins_population.packet_since(population_revision) } else { state.population.packet_since(population_revision) } };
                    if let Some((revision, packet)) = packet {
                        if send_raw(&mut socket, packet.to_string()).await.is_err(){break;}
                        population_revision=Some(revision);
                    }
                }
                if announcement_version == 1 && let Some((revision,packet))=announcements.packet_since(announcement_revision, Instant::now()) {
                    if send(&mut socket,packet).await.is_err(){break;}
                    announcement_revision=Some(revision);
                }
                if heard.elapsed()>Duration::from_secs(15){socket.metrics.event("websocket","HEARTBEAT_TIMEOUT",id);tracing::warn!(code="HEARTBEAT_TIMEOUT","world heartbeat expired");break;}
                if checked.elapsed()>=Duration::from_secs(1){
                    match auth.live_session(owner.session).await{Ok(true)=>{},Ok(false)=>{fail(&mut socket,"SESSION_REVOKED").await;leave=true;break},Err(_)=>{fail(&mut socket,"DATABASE_UNAVAILABLE").await;break}}
                    checked=Instant::now();
                }
                if audit_since.elapsed()>=Duration::from_secs(10) {
                    if move_accepted+move_rejected>0 {crate::security::connection_event(&auth,owner.session,owner.id,"world.movement","OK",json!({"accepted":move_accepted,"rejected":move_rejected,"last_rejection":last_move_code,"window_seconds":audit_since.elapsed().as_secs(),"map_id":owner.map_id})).await;}
                    move_accepted=0;move_rejected=0;last_move_code="OK";audit_since=Instant::now();
                }
                if saved.elapsed()>=Duration::from_secs(hub.config.save_seconds){
                    if let Some(p)=hub.save_snapshot(&owner) && WorldHub::persist(&auth,p).await.is_err(){fail(&mut socket,"DATABASE_UNAVAILABLE").await;break;}
                    saved=Instant::now();
                }
                let (oldest,epoch,batch,result)={
                    let state=hub.data.lock().expect("world state");
                    (state.chat.oldest(),state.chat.epoch,state.chat.batch(chat_cursor),chat_pending.and_then(|id|state.chat.result(owner.id,id)))
                };
                if chat_cursor+1<oldest {
                    if send(&mut socket,json!({"type":"chat.gap","channel_epoch":epoch,"oldest_seq":oldest.to_string()})).await.is_err(){break;}
                    chat_cursor=oldest-1;
                }
                if !batch.is_empty() {
                    let last=batch.last().expect("chat batch").seq.parse::<u64>().expect("chat sequence");
                    if send(&mut socket,json!({"type":"chat.batch","channel_epoch":epoch,"messages":batch})).await.is_err(){break;}
                    chat_cursor=last;
                }
                if let Some(result)=result && result.status=="SENT" {
                    if send(&mut socket,json!({"type":"chat.result","result":result})).await.is_err(){break;}
                    chat_pending=None;
                }
            }
        }
    }
    tracing::info!(leave, "world session ending");
    crate::security::connection_event(&auth,owner.session,owner.id,"world.leave","OK",json!({"explicit_leave":leave,"movement_accepted":move_accepted,"movement_rejected":move_rejected,"last_rejection":last_move_code,"map_id":owner.map_id})).await;
    hub.disconnect(&auth, &owner, leave).await;
    let _ = tokio::time::timeout(Duration::from_secs(1), socket.send(Message::Close(None))).await;
}
async fn send_snapshot(
    socket: &mut ObservedSocket,
    stream: Uuid,
    publication: &Publication,
) -> Result<(), ()> {
    // Entire immutable map image; watch-style coalescing is BEFORE assigning seq.
    // Full replacement conveys all enters/leaves without dropping lifecycle deltas.
    let entities = &publication.entities;
    let chunks = publication.snapshot_chunks().len();
    let id = Uuid::new_v4();
    let seq = "1";
    send(socket,json!({"type":"snapshot.begin","stream_id":stream,"seq":seq,"snapshot_id":id,"chunks":chunks,"count":entities.len(),"base_world_seq":publication.seq.to_string()})).await?;
    let mut digest = Sha256::new();
    for (index, records) in publication.snapshot_chunks().iter().enumerate() {
        let raw = format!(
            "{{\"type\":\"snapshot.chunk\",\"stream_id\":\"{stream}\",\"seq\":\"{seq}\",\"snapshot_id\":\"{id}\",\"chunk_index\":{index},\"records\":{records}}}"
        );
        digest.update((raw.len() as u32).to_be_bytes());
        digest.update(raw.as_bytes());
        send_raw(socket, raw).await?;
    }
    send(socket,json!({"type":"snapshot.end","stream_id":stream,"seq":seq,"snapshot_id":id,"sha256":format!("{:x}",digest.finalize()),"count":entities.len(),"chunks":chunks})).await
}
