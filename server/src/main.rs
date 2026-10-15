use tokio::net::TcpListener;
use vssjx_server::{apps, auth::AuthService, config::Config, logging};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::from_env().map_err(std::io::Error::other)?;
    let logs = logging::init(&config.log_filter, &config.monitoring)?;
    let result = run(config, logs.health.clone()).await;
    if result.is_err() {
        tracing::error!(
            "server stopped with an error; inspect startup stage and listener/database availability"
        );
    }
    result
}

async fn run(
    config: Config,
    log_health: logging::LogHealth,
) -> Result<(), Box<dyn std::error::Error>> {
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "server starting");
    let listener = TcpListener::bind(config.bind_addr).await.inspect_err(|error| {
        tracing::error!(listener="game", address=%config.bind_addr, kind=?error.kind(), "listener bind failed");
    })?;
    let monitor = match config.monitoring.bind_addr {
        Some(address) if address.ip().is_loopback() => Some(TcpListener::bind(address).await.inspect_err(|error| {
            tracing::error!(listener="monitor", endpoint=%address, kind=?error.kind(), "listener bind failed");
        })?),
        Some(_) => {
            return Err(std::io::Error::other("monitor listener must be loopback-only").into());
        }
        None => None,
    };
    let (auth, stage) = match config.database_url.as_deref() {
        Some(url) => {
            tracing::info!("initializing account database and migrations");
            let auth = AuthService::connect(url, config.auth)
                .await
                .map_err(std::io::Error::other)?;
            (Some(auth), "account_auth")
        }
        None => (None, "connection_only"),
    };
    let (router, monitor_router) = apps(config, auth, log_health);
    if let Some(monitor) = &monitor {
        tracing::info!(monitor_endpoint=%monitor.local_addr()?, "local monitoring listening");
    }
    tracing::info!(address = %listener.local_addr()?, stage, "Vssjx server listening");
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
    tokio::spawn(async move {
        shutdown_signal().await;
        let _ = shutdown_tx.send(true);
    });
    let game = axum::serve(
        listener,
        router.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .with_graceful_shutdown(cancelled(shutdown_rx.clone()));
    let monitoring = async move {
        if let Some(listener) = monitor {
            axum::serve(
                listener,
                monitor_router.into_make_service_with_connect_info::<std::net::SocketAddr>(),
            )
            .with_graceful_shutdown(cancelled(shutdown_rx))
            .await?;
        }
        Ok::<_, std::io::Error>(())
    };
    tokio::try_join!(async { game.await }, monitoring)?;
    tracing::info!("server stopped");
    Ok(())
}

async fn cancelled(mut signal: tokio::sync::watch::Receiver<bool>) {
    let _ = signal.wait_for(|stopping| *stopping).await;
}

async fn shutdown_signal() {
    let interrupt = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::warn!(%error, "Failed to register interrupt handler");
            std::future::pending::<()>().await;
        }
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(error) => {
                tracing::warn!(%error, "Failed to register termination handler");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! { () = interrupt => {}, () = terminate => {} }
    tracing::info!("Stopping Vssjx server");
}
