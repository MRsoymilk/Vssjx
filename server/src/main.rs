use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;
use vssjx_server::{app, app_with_auth, auth::AuthService, config::Config};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::from_env().map_err(std::io::Error::other)?;
    tracing_subscriber::fmt()
        .with_ansi(false)
        .with_env_filter(EnvFilter::new(&config.log_filter))
        .init();
    let listener = TcpListener::bind(config.bind_addr).await?;
    let (router, stage) = match config.database_url.as_deref() {
        Some(url) => {
            let auth = AuthService::connect(url, config.auth)
                .await
                .map_err(std::io::Error::other)?;
            (app_with_auth(config, auth), "account_auth")
        }
        None => (app(config), "connection_only"),
    };
    tracing::info!(address = %listener.local_addr()?, stage, "Vssjx server listening");
    axum::serve(
        listener,
        router.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
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
