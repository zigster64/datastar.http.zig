use axum::{
    response::{Html, IntoResponse, Sse},
    routing::get,
    Router,
};
use axum::response::sse::{Event, KeepAlive};
use futures::stream::{self, Stream};
use std::time::Instant;
use std::convert::Infallible;

// We use native Axum event building for maximum performance
// instead of fighting the SDK trait bounds.

const INDEX_HTML: &str = include_str!("index.html");
const SSE_HTML: &str = include_str!("sse.html");

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(index_handler))
        .route("/sse", get(sse_handler));

    let port = 8099;
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .unwrap();

    println!("Rust Axum Server running at http://localhost:{}", port);
    axum::serve(listener, app).await.unwrap();
}

async fn index_handler() -> impl IntoResponse {
    let start = Instant::now();
    let resp = Html(INDEX_HTML);
    
    let duration = start.elapsed();
    println!("Rust index handler took {} microseconds", duration.as_micros());
    
    resp
}

async fn sse_handler() -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let start = Instant::now();

    let axum_event = Event::default()
        .event("datastar-merge-fragments")
        .data(SSE_HTML);

    let duration = start.elapsed();
    println!("Rust SSE handler took {} microseconds", duration.as_micros());

    let stream = stream::once(async move { Ok(axum_event) });

    Sse::new(stream).keep_alive(KeepAlive::default())
}
