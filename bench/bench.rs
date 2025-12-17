use axum::{
    response::{Html, IntoResponse, Sse},
    routing::get,
    Router,
};
use axum::response::sse::{Event, KeepAlive};
use futures::stream::{self, Stream};
use std::time::Instant;
use std::convert::Infallible;
use datastar::prelude::*;

const INDEX_HTML: &str = include_str!("index.html");
const SSE_HTML: &str = include_str!("sse.html");

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(index_handler))
        .route("/log", get(index_handler_logged))
        .route("/sse", get(sse_handler));

    let port = 8099;
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port))
        .await
        .unwrap();

    println!("Rust Axum Server running at http://localhost:{}", port);
    axum::serve(listener, app).await.unwrap();
}

async fn index_handler() -> impl IntoResponse {
    let resp = Html(INDEX_HTML);
    resp
}

async fn index_handler_logged() -> impl IntoResponse {
    let start = Instant::now();
    let resp = Html(INDEX_HTML);
    let duration = start.elapsed();
    println!("Rust index handler took {} microseconds", duration.as_micros());
    resp
}

async fn sse_handler() -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let start = Instant::now();

    let sdk_event = PatchElements::new(SSE_HTML);
    let elements_str = sdk_event.elements.as_ref().unwrap();

    let mut data_payload = String::with_capacity(elements_str.len() + 1024);
    
    for line in elements_str.lines() {
        data_payload.push_str("elements ");
        data_payload.push_str(line);
        data_payload.push('\n');
    }

    let axum_event = Event::default()
        .event("datastar-merge-fragments")
        .data(data_payload);

    let duration = start.elapsed();
    println!("Rust SSE handler took {} microseconds", duration.as_micros());

    let stream = stream::once(async move { Ok(axum_event) });

    Sse::new(stream).keep_alive(KeepAlive::default())
}
