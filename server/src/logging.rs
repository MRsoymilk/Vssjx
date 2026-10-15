//! Bounded asynchronous JSON logging. Only application targets are allowed:
//! even RUST_LOG=trace cannot enable dependency SQL/header/body diagnostics.
use crate::config::MonitoringConfig;
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
};
use tracing_appender::non_blocking::{ErrorCounter, WorkerGuard};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

pub struct LogGuard {
    _workers: Vec<WorkerGuard>,
    pub health: LogHealth,
}
#[derive(Clone, Default)]
pub struct LogHealth {
    queues: Vec<ErrorCounter>,
    io_errors: Arc<AtomicU64>,
}
impl LogHealth {
    pub fn dropped(&self) -> usize {
        self.queues.iter().map(ErrorCounter::dropped_lines).sum()
    }
    pub fn io_errors(&self) -> u64 {
        self.io_errors.load(Ordering::Relaxed)
    }
}

pub fn init(
    filter: &str,
    config: &MonitoringConfig,
) -> Result<LogGuard, Box<dyn std::error::Error>> {
    let (console, console_guard) = tracing_appender::non_blocking::NonBlockingBuilder::default()
        .buffered_lines_limit(4096)
        .finish(io::stderr());
    let mut health = LogHealth::default();
    health.queues.push(console.error_counter());
    let mut workers = vec![console_guard];
    let file = if let Some(dir) = &config.log_dir {
        let writer = RotatingFile::new(
            dir,
            config.log_file_bytes,
            config.log_files,
            health.io_errors.clone(),
        )?;
        let (writer, guard) = tracing_appender::non_blocking::NonBlockingBuilder::default()
            .buffered_lines_limit(4096)
            .finish(writer);
        health.queues.push(writer.error_counter());
        workers.push(guard);
        Some(
            tracing_subscriber::fmt::layer()
                .json()
                .with_current_span(true)
                .with_span_list(false)
                .with_writer(writer),
        )
    } else {
        None
    };
    tracing_subscriber::registry()
        .with(EnvFilter::try_new(filter)?)
        .with(tracing_subscriber::filter::filter_fn(|meta| {
            meta.target().starts_with("vssjx_server")
        }))
        .with(
            tracing_subscriber::fmt::layer()
                .with_ansi(false)
                .with_writer(console),
        )
        .with(file)
        .try_init()?;
    Ok(LogGuard {
        _workers: workers,
        health,
    })
}

struct RotatingFile {
    dir: PathBuf,
    file: Option<File>,
    size: u64,
    limit: u64,
    files: u32,
    errors: Arc<AtomicU64>,
}
fn open_private(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.create(true).append(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}
impl RotatingFile {
    fn new(dir: &Path, limit: u64, files: u32, errors: Arc<AtomicU64>) -> io::Result<Self> {
        if limit == 0 || files == 0 {
            return Err(io::Error::other("invalid log bounds"));
        }
        fs::create_dir_all(dir)?;
        // If retention was reduced, prune only this logger's numbered files.
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let name = entry.file_name();
            if let Some(raw) = name.to_str().and_then(|n| n.strip_prefix("server.jsonl."))
                && let Ok(index) = raw.parse::<u32>()
                && index > 0
                && index >= files
                && raw == index.to_string()
            {
                fs::remove_file(entry.path())?;
            }
        }
        let file = open_private(&dir.join("server.jsonl"))?;
        let size = file.metadata()?.len();
        Ok(Self {
            dir: dir.into(),
            file: Some(file),
            size,
            limit,
            files,
            errors,
        })
    }
    fn rotate(&mut self) -> io::Result<()> {
        self.file.take();
        let oldest = if self.files == 1 {
            "server.jsonl".into()
        } else {
            format!("server.jsonl.{}", self.files - 1)
        };
        match fs::remove_file(self.dir.join(oldest)) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        for index in (1..self.files).rev() {
            let source = if index == 1 {
                "server.jsonl".into()
            } else {
                format!("server.jsonl.{}", index - 1)
            };
            match fs::rename(
                self.dir.join(source),
                self.dir.join(format!("server.jsonl.{index}")),
            ) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(e) => return Err(e),
            }
        }
        self.file = Some(open_private(&self.dir.join("server.jsonl"))?);
        self.size = 0;
        Ok(())
    }
    fn append(&mut self, bytes: &[u8]) -> io::Result<()> {
        if bytes.len() as u64 > self.limit {
            return Err(io::Error::other("log record exceeds file bound"));
        }
        if self.file.is_none() {
            let file = open_private(&self.dir.join("server.jsonl"))?;
            self.size = file.metadata()?.len();
            self.file = Some(file);
        }
        if self.size + bytes.len() as u64 > self.limit {
            self.rotate()?;
        }
        self.file.as_mut().expect("open log").write_all(bytes)?;
        self.size += bytes.len() as u64;
        Ok(())
    }
}
impl Write for RotatingFile {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        match self.append(bytes) {
            Ok(()) => Ok(bytes.len()),
            Err(error) => {
                self.errors.fetch_add(1, Ordering::Relaxed);
                Err(error)
            }
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        if let Some(file) = &mut self.file {
            file.flush()
        } else {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn file_rotation_failure_is_counted_and_can_recover() {
        let dir = PathBuf::from("/tmp/opencode")
            .join(format!("vssjx-log-fault-{}", uuid::Uuid::new_v4()));
        let errors = Arc::new(AtomicU64::new(0));
        let mut writer = RotatingFile::new(&dir, 8, 2, errors.clone()).unwrap();
        writer.write_all(b"first\n").unwrap();
        // A directory where the rotated file belongs simulates a real FS error.
        fs::create_dir(dir.join("server.jsonl.1")).unwrap();
        assert!(writer.write_all(b"second\n").is_err());
        assert_eq!(errors.load(Ordering::Relaxed), 1);
        fs::remove_dir(dir.join("server.jsonl.1")).unwrap();
        writer.write_all(b"third\n").unwrap();
        drop(writer);
        assert_eq!(
            fs::read_to_string(dir.join("server.jsonl")).unwrap(),
            "third\n"
        );
        assert_eq!(
            fs::read_to_string(dir.join("server.jsonl.1")).unwrap(),
            "first\n"
        );
        for entry in fs::read_dir(&dir).unwrap() {
            fs::remove_file(entry.unwrap().path()).unwrap();
        }
        fs::remove_dir(dir).unwrap();
    }
    #[test]
    fn a_blocked_writer_drops_bounded_queue_records_without_blocking_callers() {
        struct Gate {
            entered: std::sync::mpsc::Sender<()>,
            release: std::sync::mpsc::Receiver<()>,
            first: bool,
        }
        impl Write for Gate {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                if self.first {
                    self.first = false;
                    self.entered.send(()).unwrap();
                    self.release.recv().unwrap();
                }
                Ok(bytes.len())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let gate = Gate {
            entered: entered_tx,
            release: release_rx,
            first: true,
        };
        let (mut writer, guard) = tracing_appender::non_blocking::NonBlockingBuilder::default()
            .buffered_lines_limit(2)
            .finish(gate);
        let health = LogHealth {
            queues: vec![writer.error_counter()],
            io_errors: Arc::new(AtomicU64::new(0)),
        };
        writer.write_all(b"start\n").unwrap();
        entered_rx
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap();
        for _ in 0..100 {
            writer.write_all(b"event\n").unwrap();
        }
        assert!(health.dropped() >= 98);
        release_tx.send(()).unwrap();
        drop(guard);
    }
    #[test]
    fn rotation_bounds_size_and_count_and_preserves_unrelated_files() {
        let dir =
            PathBuf::from("/tmp/opencode").join(format!("vssjx-logs-{}", uuid::Uuid::new_v4()));
        let errors = Arc::new(AtomicU64::new(0));
        let mut writer = RotatingFile::new(&dir, 64, 3, errors.clone()).unwrap();
        fs::write(dir.join("unrelated.txt"), "preserve").unwrap();
        for _ in 0..20 {
            writer.write_all(b"{\"event\":\"bounded\"}\n").unwrap();
        }
        drop(writer);
        for name in ["server.jsonl", "server.jsonl.1", "server.jsonl.2"] {
            let path = dir.join(name);
            assert!(fs::metadata(&path).unwrap().len() <= 64);
            for line in fs::read_to_string(&path).unwrap().lines() {
                serde_json::from_str::<serde_json::Value>(line).unwrap();
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                assert_eq!(
                    fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                    0o600
                );
            }
        }
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 4);
        let mut writer = RotatingFile::new(&dir, 64, 1, errors.clone()).unwrap();
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 2);
        assert!(writer.write_all(&[0; 65]).is_err());
        assert_eq!(errors.load(Ordering::Relaxed), 1);
        drop(writer);
        for entry in fs::read_dir(&dir).unwrap() {
            fs::remove_file(entry.unwrap().path()).unwrap();
        }
        fs::remove_dir(dir).unwrap();
    }
}
