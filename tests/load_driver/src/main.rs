//! Real protocol clients. Test credentials stay in memory; no direct DB seeding.
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, VecDeque},
    env, fs,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering::Relaxed},
    },
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    sync::Semaphore,
};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use uuid::Uuid;
mod world_wire;

#[derive(Deserialize)]
struct Config {
    base: String,
    map_path: String,
    output: String,
    players: usize,
    admission_seconds: u64,
    warmup_seconds: u64,
    stages: Vec<Stage>,
}
#[derive(Clone, Deserialize, Serialize)]
struct Stage {
    name: String,
    players: usize,
    moving_percent: usize,
    seconds: u64,
}
struct Account {
    id: Uuid,
    token: String,
}
fn unix_time() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}
#[derive(Default)]
struct Hist {
    bins: Vec<u64>,
    count: u64,
    sum: f64,
    max: f64,
}
impl Hist {
    fn add(&mut self, elapsed: Duration) {
        let ms = elapsed.as_secs_f64() * 1000.0;
        if self.bins.is_empty() {
            self.bins = vec![0; 60001]
        };
        self.bins[(ms.ceil() as usize).min(60000)] += 1;
        self.count += 1;
        self.sum += ms;
        self.max = self.max.max(ms);
    }
    fn value(&self) -> Value {
        let q = |ratio: f64| {
            let rank = (self.count as f64 * ratio).ceil() as u64;
            let mut sum = 0;
            for (i, n) in self.bins.iter().enumerate() {
                sum += n;
                if sum >= rank && rank > 0 {
                    return Some(i);
                }
            }
            None
        };
        json!({"count":self.count,"mean_ms":if self.count>0{self.sum/self.count as f64}else{0.0},"p50_ms":q(0.5),"p95_ms":q(0.95),"p99_ms":q(0.99),"max_ms":self.max})
    }
}
struct Stats {
    measure: AtomicBool,
    stop: AtomicBool,
    active: AtomicUsize,
    peak: AtomicUsize,
    ready: AtomicUsize,
    full_seen: AtomicUsize,
    full_live: AtomicUsize,
    finished: AtomicUsize,
    bytes: AtomicU64,
    packets: AtomicU64,
    snapshots: AtomicU64,
    full_snapshots: AtomicU64,
    records: AtomicU64,
    moves_planned: AtomicU64,
    moves_sent: AtomicU64,
    moves_unobserved: AtomicU64,
    schedule_missed: AtomicU64,
    pings_sent: AtomicU64,
    pings_unanswered: AtomicU64,
    chat_sent: AtomicU64,
    chat_accepted: AtomicU64,
    chat_deliveries: AtomicU64,
    errors: Mutex<HashMap<String, u64>>,
    admission: Mutex<Hist>,
    first_sync: Mutex<Hist>,
    ping: Mutex<Hist>,
    movement: Mutex<Hist>,
    chat: Mutex<Hist>,
    snapshot_interval: Mutex<Hist>,
    start: Mutex<Option<Instant>>,
    chat_times: Mutex<HashMap<String, Instant>>,
    client_updates: Vec<AtomicU64>,
}
impl Stats {
    fn new(players: usize) -> Self {
        Self {
            measure: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            active: AtomicUsize::new(0),
            peak: AtomicUsize::new(0),
            ready: AtomicUsize::new(0),
            full_seen: AtomicUsize::new(0),
            full_live: AtomicUsize::new(0),
            finished: AtomicUsize::new(0),
            bytes: AtomicU64::new(0),
            packets: AtomicU64::new(0),
            snapshots: AtomicU64::new(0),
            full_snapshots: AtomicU64::new(0),
            records: AtomicU64::new(0),
            moves_planned: AtomicU64::new(0),
            moves_sent: AtomicU64::new(0),
            moves_unobserved: AtomicU64::new(0),
            schedule_missed: AtomicU64::new(0),
            pings_sent: AtomicU64::new(0),
            pings_unanswered: AtomicU64::new(0),
            chat_sent: AtomicU64::new(0),
            chat_accepted: AtomicU64::new(0),
            chat_deliveries: AtomicU64::new(0),
            errors: Mutex::new(HashMap::new()),
            admission: Mutex::new(Hist::default()),
            first_sync: Mutex::new(Hist::default()),
            ping: Mutex::new(Hist::default()),
            movement: Mutex::new(Hist::default()),
            chat: Mutex::new(Hist::default()),
            snapshot_interval: Mutex::new(Hist::default()),
            start: Mutex::new(None),
            chat_times: Mutex::new(HashMap::new()),
            client_updates: (0..players).map(|_| AtomicU64::new(0)).collect(),
        }
    }
    fn error(&self, code: &str) {
        *self
            .errors
            .lock()
            .unwrap()
            .entry(code.to_owned())
            .or_default() += 1;
    }
    fn report(&self, stage: &Stage, elapsed: f64) -> Value {
        json!({"stage":stage,"measured_seconds":elapsed,"authenticated_total":self.ready.load(Relaxed),"peak_active":self.peak.load(Relaxed),"active_at_end":self.active.load(Relaxed),"clients_ever_saw_entire_population":self.full_seen.load(Relaxed),"live_clients_saw_entire_population":self.full_live.load(Relaxed),"payload_bytes":self.bytes.load(Relaxed),"payload_mib_per_second":self.bytes.load(Relaxed) as f64/elapsed/1048576.0,"packets":self.packets.load(Relaxed),"snapshots":self.snapshots.load(Relaxed),"full_population_snapshots":self.full_snapshots.load(Relaxed),"entity_records_delivered":self.records.load(Relaxed),"moves_planned":self.moves_planned.load(Relaxed),"moves_sent":self.moves_sent.load(Relaxed),"moves_unobserved_at_end":self.moves_unobserved.load(Relaxed),"missed_scheduled_actions":self.schedule_missed.load(Relaxed),"pings_sent":self.pings_sent.load(Relaxed),"pings_unanswered_at_end":self.pings_unanswered.load(Relaxed),"chat_sends":self.chat_sent.load(Relaxed),"chat_accepted":self.chat_accepted.load(Relaxed),"chat_deliveries":self.chat_deliveries.load(Relaxed),"errors":*self.errors.lock().unwrap(),"ticket_to_auth_ready":self.admission.lock().unwrap().value(),"ticket_to_first_valid_snapshot":self.first_sync.lock().unwrap().value(),"ping_roundtrip":self.ping.lock().unwrap().value(),"movement_snapshot_observation":self.movement.lock().unwrap().value(),"chat_delivery":self.chat.lock().unwrap().value(),"snapshot_interval":self.snapshot_interval.lock().unwrap().value()})
    }
}

async fn http(
    base: &str,
    path: &str,
    payload: Value,
    token: Option<&str>,
) -> Result<Value, String> {
    let address = base.strip_prefix("http://").ok_or("LOOPBACK_HTTP_ONLY")?;
    if !address.starts_with("127.0.0.1:") {
        return Err("LOOPBACK_HTTP_ONLY".into());
    }
    let body = payload.to_string();
    let auth = token
        .map(|t| format!("Authorization: Bearer {t}\r\n"))
        .unwrap_or_default();
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: {address}\r\nContent-Type: application/json\r\nConnection: close\r\n{auth}Content-Length: {}\r\n\r\n{body}",
        body.len()
    );
    let operation = async {
        let mut stream = TcpStream::connect(address)
            .await
            .map_err(|_| "HTTP_CONNECT")?;
        stream
            .write_all(request.as_bytes())
            .await
            .map_err(|_| "HTTP_WRITE")?;
        let mut bytes = Vec::new();
        stream
            .take(65537)
            .read_to_end(&mut bytes)
            .await
            .map_err(|_| "HTTP_READ")?;
        let split = bytes
            .windows(4)
            .position(|v| v == b"\r\n\r\n")
            .ok_or("HTTP_HEADERS")?;
        let head = std::str::from_utf8(&bytes[..split]).map_err(|_| "HTTP_HEADERS")?;
        let code = head.split_whitespace().nth(1).unwrap_or("");
        let value: Value = serde_json::from_slice(&bytes[split + 4..]).map_err(|_| "HTTP_JSON")?;
        if code != "200" && code != "201" {
            return Err(value["code"].as_str().unwrap_or("HTTP_STATUS").to_owned());
        }
        Ok(value)
    };
    tokio::time::timeout(Duration::from_secs(15), operation)
        .await
        .map_err(|_| "HTTP_TIMEOUT".to_owned())?
}

#[derive(Deserialize)]
struct Record<'a> {
    net_id: u32,
    id: Uuid,
    #[serde(borrow)]
    last_input_seq: &'a str,
    #[serde(borrow)]
    entity_revision: &'a str,
}
#[derive(Deserialize)]
#[serde(tag = "type")]
enum Incoming<'a> {
    #[serde(rename = "auth.ready")]
    Ready {
        game_session_id: Uuid,
        connection_epoch: String,
        world_epoch: String,
        stream_id: Uuid,
        character_id: Uuid,
        world_stream_id: Uuid,
        world_sync_version: u32,
    },
    #[serde(rename = "snapshot.begin")]
    Begin {
        stream_id: Uuid,
        seq: String,
        snapshot_id: Uuid,
        chunks: usize,
        count: usize,
        base_world_seq: String,
    },
    #[serde(rename = "snapshot.chunk")]
    Chunk {
        stream_id: Uuid,
        seq: String,
        snapshot_id: Uuid,
        chunk_index: usize,
        #[serde(borrow)]
        records: Vec<Record<'a>>,
    },
    #[serde(rename = "snapshot.end")]
    End {
        stream_id: Uuid,
        seq: String,
        snapshot_id: Uuid,
        chunks: usize,
        count: usize,
        sha256: String,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "error")]
    Error { code: String },
    #[serde(rename = "chat.ready")]
    ChatReady {
        oldest_seq: String,
        channel_epoch: Uuid,
    },
    #[serde(rename = "chat.gap")]
    ChatGap {
        oldest_seq: String,
        channel_epoch: Uuid,
    },
    #[serde(rename = "chat.batch")]
    ChatBatch {
        channel_epoch: Uuid,
        messages: Vec<ChatRecord>,
    },
    #[serde(rename = "chat.result")]
    ChatResult { result: Value },
}
#[derive(Deserialize)]
struct ChatRecord {
    seq: String,
    text: String,
}
struct Assembly {
    id: Uuid,
    seq: u64,
    chunks: usize,
    count: usize,
    index: usize,
    received: usize,
    digest: Sha256,
    seen: Vec<bool>,
    own_seq: Option<u64>,
    baseline: u64,
    network: Vec<(u32, Uuid, u64, u64)>,
}

async fn bot(
    index: usize,
    account: Arc<Account>,
    accounts: Arc<HashMap<Uuid, usize>>,
    stage: Stage,
    endpoint: (String, String),
    stats: Arc<Stats>,
    gate: Arc<Semaphore>,
) {
    let outcome = run_bot(
        index,
        account,
        accounts,
        stage,
        endpoint,
        stats.clone(),
        gate,
    )
    .await;
    if let Err(error) = outcome {
        stats.error(&error);
    }
    stats.finished.fetch_add(1, Relaxed);
}
async fn run_bot(
    index: usize,
    account: Arc<Account>,
    accounts: Arc<HashMap<Uuid, usize>>,
    stage: Stage,
    endpoint: (String, String),
    stats: Arc<Stats>,
    gate: Arc<Semaphore>,
) -> Result<(), String> {
    let (base, hash) = endpoint;
    let permit = gate.acquire_owned().await.map_err(|_| "ADMISSION_GATE")?;
    if stats.stop.load(Relaxed) {
        return Ok(());
    }
    let joined = Instant::now();
    let ticket = http(
        &base,
        "/api/v1/world/ticket",
        json!({"character_id":account.id,"protocol_version":1,"config_hash":hash}),
        Some(&account.token),
    )
    .await?;
    let url = base.replacen("http://", "ws://", 1) + "/api/v1/world/ws";
    let (mut ws, _) = tokio::time::timeout(Duration::from_secs(10), connect_async(url))
        .await
        .map_err(|_| "WS_CONNECT_TIMEOUT")?
        .map_err(|_| "WS_CONNECT")?;
    ws.send(Message::Text(json!({"type":"auth.exchange","ticket":ticket["ticket"],"protocol_version":1,"config_hash":hash,"world_sync_version":2}).to_string().into())).await.map_err(|_|"WS_EXCHANGE")?;
    let first = tokio::time::timeout(Duration::from_secs(15), ws.next())
        .await
        .map_err(|_| "AUTH_READY_TIMEOUT")?
        .ok_or("AUTH_READY_EOF")?
        .map_err(|_| "AUTH_READY_READ")?;
    let text = first.to_text().map_err(|_| "AUTH_READY_TYPE")?;
    let ready: Incoming = serde_json::from_str(text).map_err(|_| "AUTH_READY_JSON")?;
    let (game, epoch, world, stream, world_stream) = match ready {
        Incoming::Ready {
            game_session_id,
            connection_epoch,
            world_epoch,
            stream_id,
            character_id,
            world_stream_id,
            world_sync_version: 2,
        } if character_id == account.id => (
            game_session_id,
            connection_epoch,
            world_epoch,
            stream_id,
            world_stream_id,
        ),
        Incoming::Error { code } => return Err(code),
        _ => return Err("AUTH_READY_IDENTITY".into()),
    };
    stats.admission.lock().unwrap().add(joined.elapsed());
    stats.ready.fetch_add(1, Relaxed);
    let active = stats.active.fetch_add(1, Relaxed) + 1;
    stats.peak.fetch_max(active, Relaxed);
    drop(permit);
    let mut full = false;
    let mut moves: VecDeque<(u64, Instant)> = VecDeque::new();
    let mut ping_pending: Option<(Instant, bool)> = None;
    let mut model = world_wire::Model::new(world_stream, accounts.clone(), stage.players, index);
    let result=async{
        let mut assembly:Option<Assembly>=None;let mut sequence=0_u64;let mut first_sync=false;
        let mut chat_epoch=None;let mut chat_cursor=0_u64;
        let mut last_snapshot=None;let mut latest_packet=Instant::now();
        let mut input=0_u64;
        let mut schedule=tokio::time::interval(Duration::from_millis(25));schedule.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut next_ping=Instant::now()+Duration::from_millis(500+(index as u64*379)%2500);
        let mut next_move:Option<Instant>=None;
        let mut next_chat=0_u64;
        let mut measured=false;
        let targets=[[24,16],[10,22],[24,22],[10,16]];
        loop{
            if stats.stop.load(Relaxed){break;}
            tokio::select!{
                packet=ws.next()=>{
                    let Some(Ok(packet))=packet else{return Err("WS_DISCONNECTED".into())};
                    latest_packet=Instant::now();
                    let recording=stats.measure.load(Relaxed);
                    if let Message::Binary(raw)=packet{
                        let changed=model.apply(&raw)?;
                        let count=model.count();
                        if count==stage.players&&!full{full=true;stats.full_seen.fetch_add(1,Relaxed);stats.full_live.fetch_add(1,Relaxed);}
                        if recording{
                            stats.bytes.fetch_add(raw.len() as u64,Relaxed);stats.packets.fetch_add(1,Relaxed);
                            stats.snapshots.fetch_add(1,Relaxed);stats.records.fetch_add(changed as u64,Relaxed);
                            if count==stage.players{stats.full_snapshots.fetch_add(1,Relaxed);stats.client_updates[index].fetch_add(1,Relaxed);}
                            if let Some(last)=last_snapshot{stats.snapshot_interval.lock().unwrap().add(Instant::now()-last);}
                            last_snapshot=Some(Instant::now());
                            while moves.front().is_some_and(|(seq,_)|*seq<=model.own_input){let (_,at)=moves.pop_front().unwrap();stats.movement.lock().unwrap().add(at.elapsed());}
                        }
                        continue;
                    }
                    let Message::Text(text)=packet else{if matches!(packet,Message::Close(_)){return Err("WS_CLOSED".into())}continue};
                    if recording{stats.bytes.fetch_add(text.len() as u64,Relaxed);stats.packets.fetch_add(1,Relaxed);}
                    let message:Incoming=serde_json::from_str(&text).map_err(|_|"PROTOCOL_JSON")?;
                    match message{
                        Incoming::Begin{stream_id,seq,snapshot_id,chunks,count,base_world_seq}=>{
                            let seq=seq.parse::<u64>().map_err(|_|"SNAPSHOT_SEQUENCE")?;
                            if stream_id!=stream||seq!=sequence+1||assembly.is_some()||count==0||count>stage.players||chunks!=count.div_ceil(32){return Err("SNAPSHOT_BEGIN".into());}
                            assembly=Some(Assembly{id:snapshot_id,seq,chunks,count,index:0,received:0,digest:Sha256::new(),seen:vec![false;stage.players],own_seq:None,baseline:base_world_seq.parse().map_err(|_|"WORLD_SEQUENCE")?,network:Vec::new()});
                        },
                        Incoming::Chunk{stream_id,seq,snapshot_id,chunk_index,records}=>{
                            let current=assembly.as_mut().ok_or("CHUNK_WITHOUT_BEGIN")?;
                            if stream_id!=stream||seq!=current.seq.to_string()||snapshot_id!=current.id||chunk_index!=current.index||records.is_empty()||records.len()>32{return Err("SNAPSHOT_CHUNK".into());}
                            current.digest.update((text.len() as u32).to_be_bytes());current.digest.update(text.as_bytes());
                            for record in records{
                                let other=*accounts.get(&record.id).ok_or("UNKNOWN_ENTITY")?;
                                if other>=stage.players||current.seen[other]{return Err("DUPLICATE_ENTITY".into());}
                                current.seen[other]=true;current.received+=1;
                                current.network.push((record.net_id,record.id,record.last_input_seq.parse::<u64>().map_err(|_|"INPUT_SEQUENCE")?,record.entity_revision.parse::<u64>().map_err(|_|"ENTITY_REVISION")?));
                                if record.id==account.id{current.own_seq=Some(record.last_input_seq.parse::<u64>().map_err(|_|"INPUT_SEQUENCE")?);}
                            }
                            current.index+=1;
                        },
                        Incoming::End{stream_id,seq,snapshot_id,chunks,count,sha256}=>{
                            let current=assembly.take().ok_or("END_WITHOUT_BEGIN")?;
                            if stream_id!=stream||seq!=current.seq.to_string()||snapshot_id!=current.id||chunks!=current.chunks||count!=current.count||current.index!=chunks||current.received!=count||current.own_seq.is_none()||format!("{:x}",current.digest.finalize())!=sha256{return Err("SNAPSHOT_INTEGRITY".into());}
                            sequence=current.seq;
                            model.install(current.baseline,current.network)?;
                            if !first_sync{first_sync=true;stats.first_sync.lock().unwrap().add(joined.elapsed());}
                            if count==stage.players&&!full{full=true;stats.full_seen.fetch_add(1,Relaxed);stats.full_live.fetch_add(1,Relaxed);}
                            if recording{
                                stats.snapshots.fetch_add(1,Relaxed);stats.records.fetch_add(count as u64,Relaxed);
                                if count==stage.players{stats.full_snapshots.fetch_add(1,Relaxed);stats.client_updates[index].fetch_add(1,Relaxed);}
                                if let Some(last)=last_snapshot{stats.snapshot_interval.lock().unwrap().add(Instant::now()-last);}
                                last_snapshot=Some(Instant::now());
                                while moves.front().is_some_and(|(seq,_)|*seq<=current.own_seq.unwrap()){
                                    let (_,at)=moves.pop_front().unwrap();stats.movement.lock().unwrap().add(at.elapsed());
                                }
                            }
                        },
                        Incoming::Pong=>{if let Some((at,true))=ping_pending.take() && recording{stats.ping.lock().unwrap().add(at.elapsed());}},
                        Incoming::Error{code}=>{stats.error(&code);},
                        Incoming::ChatReady{oldest_seq,channel_epoch}=>{chat_epoch=Some(channel_epoch);chat_cursor=oldest_seq.parse::<u64>().map_err(|_|"CHAT_SEQUENCE")?-1;},
                        Incoming::ChatGap{oldest_seq,channel_epoch}=>{if chat_epoch!=Some(channel_epoch){return Err("CHAT_EPOCH".into());}chat_cursor=oldest_seq.parse::<u64>().map_err(|_|"CHAT_SEQUENCE")?-1;stats.error("CHAT_GAP");},
                        Incoming::ChatBatch{channel_epoch,messages}=>{
                            if chat_epoch!=Some(channel_epoch){return Err("CHAT_EPOCH".into());}
                            for message in messages{
                                if message.seq!=(chat_cursor+1).to_string(){return Err("CHAT_SEQUENCE".into());}chat_cursor+=1;
                                if recording && let Some(at)=stats.chat_times.lock().unwrap().get(&message.text){stats.chat.lock().unwrap().add(at.elapsed());stats.chat_deliveries.fetch_add(1,Relaxed);}
                            }
                        },
                        Incoming::ChatResult{result}=>{
                            if result["status"]=="SENT"&&recording{stats.chat_accepted.fetch_add(1,Relaxed);}
                            if result["status"]=="REJECTED"{stats.error(result["code"].as_str().unwrap_or("CHAT_REJECTED"));}
                        },
                        Incoming::Ready{..}=>return Err("DUPLICATE_AUTH_READY".into())
                    }
                },
                _=schedule.tick()=>{
                    let now=Instant::now();let recording=stats.measure.load(Relaxed);
                    if latest_packet.elapsed()>Duration::from_secs(15){return Err("SERVER_SILENCE_TIMEOUT".into());}
                    if now>=next_ping{
                        next_ping+=Duration::from_secs(3);
                        if now>=next_ping{stats.schedule_missed.fetch_add(1,Relaxed);next_ping=now+Duration::from_secs(3);}
                        if ping_pending.is_none(){ws.send(Message::Text("{\"type\":\"ping\"}".into())).await.map_err(|_|"PING_WRITE")?;ping_pending=Some((now,recording));if recording{stats.pings_sent.fetch_add(1,Relaxed);}}
                        else if recording{stats.schedule_missed.fetch_add(1,Relaxed);}
                    }
                    if recording&&!measured{measured=true;next_move=Some(now+Duration::from_millis((index as u64*431)%2000));last_snapshot=None;}
                    if recording&&index*100<stage.players*stage.moving_percent&&first_sync&&now>=next_move.unwrap(){
                        stats.moves_planned.fetch_add(1,Relaxed);next_move=Some(next_move.unwrap()+Duration::from_secs(2));
                        if now>=next_move.unwrap(){stats.schedule_missed.fetch_add(1,Relaxed);next_move=Some(now+Duration::from_secs(2));}
                        input+=1;
                        let target=targets[(input as usize+index)%targets.len()];
                        ws.send(Message::Text(json!({"type":"world.move_to","game_session_id":game,"connection_epoch":epoch,"world_epoch":world,"input_seq":input.to_string(),"target":target}).to_string().into())).await.map_err(|_|"MOVE_WRITE")?;
                        stats.moves_sent.fetch_add(1,Relaxed);moves.push_back((input,now));
                    }
                    if recording{
                        let start=stats.start.lock().unwrap().unwrap();let second=now.duration_since(start).as_secs();
                        // Exactly one planned public message globally each second, rotating sender.
                        if second as usize%stage.players==index && second>=next_chat{
                            next_chat=second+stage.players as u64;
                            let text=format!("capacity:{}:{second}",stage.name);stats.chat_times.lock().unwrap().insert(text.clone(),now);
                            ws.send(Message::Text(json!({"type":"chat.send","client_message_id":Uuid::new_v4(),"channel":"public","text":text}).to_string().into())).await.map_err(|_|"CHAT_WRITE")?;
                            stats.chat_sent.fetch_add(1,Relaxed);
                        }
                    }
                }
            }
        }
        Ok(())
    }.await;
    stats
        .moves_unobserved
        .fetch_add(moves.len() as u64, Relaxed);
    if ping_pending.is_some_and(|(_, recording)| recording) {
        stats.pings_unanswered.fetch_add(1, Relaxed);
    }
    // TCP close instead of waiting for 1000 graceful position-save roundtrips.
    drop(ws);
    stats.active.fetch_sub(1, Relaxed);
    if full {
        stats.full_live.fetch_sub(1, Relaxed);
    }
    result
}

#[tokio::main]
async fn main() {
    let config: Config = serde_json::from_slice(
        &fs::read(env::args().nth(1).expect("config path")).expect("config file"),
    )
    .expect("config JSON");
    let map = fs::read(&config.map_path).expect("map file");
    let hash = format!("{:x}", Sha256::digest(&map));
    let parsed: Value = serde_json::from_slice(&map).unwrap();
    for [x, y] in [[24, 16], [10, 22], [24, 22], [10, 16]] {
        assert_eq!(parsed["blocked"][y * 32 + x], false);
    }
    let password = format!("capacity-{}", Uuid::new_v4());
    let setup_at = Instant::now();
    let mut setup_hist = Hist::default();
    let mut accounts = Vec::new();
    // Two concurrent workers match the production-default Argon2 permit count.
    for pair in (0..config.players).step_by(2) {
        let mut tasks = tokio::task::JoinSet::new();
        for index in pair..(pair + 2).min(config.players) {
            let base = config.base.clone();
            let password = password.clone();
            tasks.spawn(async move{
            let start=Instant::now();let name=format!("capacity_{index:04}");
            http(&base,"/api/v1/auth/register",json!({"username":name,"password":password}),None).await?;
            let login=http(&base,"/api/v1/auth/login",json!({"username":name,"password":password}),None).await?;
            let token=login["access_token"].as_str().ok_or("LOGIN_TOKEN")?.to_owned();
            let created=http(&base,"/api/v1/characters",json!({"operation_id":Uuid::new_v4(),"display_name":format!("压测{index:04}"),"job":index%3,"gender":index%2,"school":0,"rules_version":"creation-v1"}),Some(&token)).await?;
            let id=Uuid::parse_str(created["character"]["id"].as_str().ok_or("CHARACTER_ID")?).map_err(|_|"CHARACTER_UUID")?;
            Ok::<_,String>((index,Arc::new(Account{id,token}),start.elapsed()))
        });
        }
        let mut result = Vec::new();
        while let Some(value) = tasks.join_next().await {
            result.push(
                value
                    .expect("setup task")
                    .unwrap_or_else(|code| panic!("isolated setup failed: {code}")),
            );
        }
        result.sort_by_key(|v| v.0);
        for (_, account, duration) in result {
            accounts.push(account);
            setup_hist.add(duration);
        }
        if accounts.len() % 100 == 0 {
            println!(
                "{}",
                json!({"event":"setup","created":accounts.len(),"elapsed_seconds":setup_at.elapsed().as_secs_f64()})
            );
        }
    }
    let membership = Arc::new(
        accounts
            .iter()
            .enumerate()
            .map(|(i, a)| (a.id, i))
            .collect::<HashMap<_, _>>(),
    );
    let setup_seconds = setup_at.elapsed().as_secs_f64();
    let mut results = Vec::new();
    for stage in &config.stages {
        assert!(stage.players <= accounts.len());
        println!("{}", json!({"event":"stage_start","stage":stage}));
        let stats = Arc::new(Stats::new(stage.players));
        let gate = Arc::new(Semaphore::new(16));
        let mut tasks = tokio::task::JoinSet::new();
        let admission_at = Instant::now();
        for (index, account) in accounts.iter().take(stage.players).enumerate() {
            tasks.spawn(bot(
                index,
                account.clone(),
                membership.clone(),
                stage.clone(),
                (config.base.clone(), hash.clone()),
                stats.clone(),
                gate.clone(),
            ));
        }
        let deadline = Instant::now() + Duration::from_secs(config.admission_seconds);
        while stats.ready.load(Relaxed) < stage.players && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        let ramp_seconds = admission_at.elapsed().as_secs_f64();
        tokio::time::sleep(Duration::from_secs(config.warmup_seconds)).await;
        while (stats.active.load(Relaxed) != stage.players
            || stats.full_live.load(Relaxed) != stage.players)
            && Instant::now() < deadline
        {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        let active_start = stats.active.load(Relaxed);
        let full_start = stats.full_live.load(Relaxed);
        let measured_at = Instant::now();
        let measured_unix = unix_time();
        *stats.start.lock().unwrap() = Some(measured_at);
        stats.measure.store(true, Relaxed);
        println!(
            "{}",
            json!({"event":"measure_start","stage":stage.name,"active":active_start,"full_visibility":full_start,"ramp_seconds":ramp_seconds})
        );
        tokio::time::sleep(Duration::from_secs(stage.seconds)).await;
        stats.measure.store(false, Relaxed);
        let elapsed = measured_at.elapsed().as_secs_f64();
        let mut report = stats.report(stage, elapsed);
        report["world_sync_version"] = json!(2);
        report["state_updates"] = report["snapshots"].clone();
        report["full_population_state_updates"] = report["full_population_snapshots"].clone();
        report["initial_snapshot_installs"] = json!(stats.first_sync.lock().unwrap().count);
        report["minimum_client_state_updates"] = json!(
            stats
                .client_updates
                .iter()
                .map(|v| v.load(Relaxed))
                .min()
                .unwrap_or(0)
        );
        report["replication_contract"] = json!(
            "initial snapshot plus ordered VWD2 deltas; legacy snapshot counters count reconstructed state observations, not repeated full snapshots"
        );
        report["measure_start_unix"] = json!(measured_unix);
        report["measure_end_unix"] = json!(unix_time());
        report["active_at_start"] = json!(active_start);
        report["full_visibility_at_start"] = json!(full_start);
        report["ramp_seconds"] = json!(ramp_seconds);
        stats.stop.store(true, Relaxed);
        let shutdown = async { while tasks.join_next().await.is_some() {} };
        let _ = tokio::time::timeout(Duration::from_secs(5), shutdown).await;
        tasks.abort_all();
        while tasks.join_next().await.is_some() {}
        report["moves_unobserved_at_end"] = json!(stats.moves_unobserved.load(Relaxed));
        report["pings_unanswered_at_end"] = json!(stats.pings_unanswered.load(Relaxed));
        report["errors"] = json!(*stats.errors.lock().unwrap());
        println!("{}", json!({"event":"stage_result","result":report}));
        results.push(report);
        fs::write(&config.output,serde_json::to_vec_pretty(&json!({"setup":{"players":accounts.len(),"seconds":setup_seconds,"register_login_create":setup_hist.value()},"results":results})).unwrap()).unwrap();
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn latency_histogram_counts_all_samples_and_has_explicit_empty_quantiles() {
        let mut hist = Hist::default();
        assert!(hist.value()["p95_ms"].is_null());
        for ms in [1, 10, 100, 1000] {
            hist.add(Duration::from_millis(ms));
        }
        let report = hist.value();
        assert_eq!(report["count"], 4);
        assert_eq!(report["p50_ms"], 10);
        assert_eq!(report["p95_ms"], 1000);
    }

    #[test]
    fn histogram_overflow_bucket_retains_the_real_maximum() {
        let mut hist = Hist::default();
        hist.add(Duration::from_millis(65000));
        assert_eq!(hist.value()["p95_ms"], 60000);
        assert_eq!(hist.value()["max_ms"], 65000.0);
    }
}
