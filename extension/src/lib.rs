//! AI Director extension.
//!
//! The director mod calls this on the server. `send_state` returns at once; a background thread posts
//! the state to the companion over loopback HTTP and hands its reply back to SQF through the
//! `ExtensionCallback` mission event handler (name `ai_director`, function `decision` or `error`).
//! The extension never talks to the internet, so the game keeps running whatever the companion does.

use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use arma_rs::{Context, ContextState, Extension, arma};

pub const CALLBACK_NAME: &str = "ai_director";
pub const DEFAULT_URL: &str = "http://127.0.0.1:47800";
/// A decision can take Claude up to ~20 s; allow for retries in the companion.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(90);
/// Decisions are small JSON objects; anything larger is a companion bug.
const MAX_DECISION_BYTES: usize = 8 * 1024;

struct Companion {
    url: Mutex<String>,
}

/// Set while a request is with the companion, so the game never queues up a backlog of states.
struct InFlight(AtomicBool);

#[arma]
fn init() -> Extension {
    build()
}

pub fn build() -> Extension {
    Extension::build()
        .command("version", version)
        .command("set_url", set_url)
        .command("send_state", send_state)
        .state(Companion {
            url: Mutex::new(DEFAULT_URL.to_string()),
        })
        .state(InFlight(AtomicBool::new(false)))
        .finish()
}

fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

fn set_url(ctx: Context, url: String) -> Result<String, String> {
    if !is_loopback_url(&url) {
        return Err(format!("companion URL must be http on the loopback interface: {url}"));
    }
    let companion = ctx.global().get::<Companion>().ok_or("missing companion state")?;
    *companion.url.lock().map_err(|e| e.to_string())? = url.trim_end_matches('/').to_string();
    Ok(url)
}

/// Queues `state` (a JSON object) for the companion. Returns "sent", or "busy" if the previous state
/// is still being decided on.
fn send_state(ctx: Context, state: String) -> Result<&'static str, String> {
    serde_json::from_str::<serde_json::Value>(&state)
        .map_err(|e| format!("state is not valid JSON: {e}"))?;
    let url = {
        let companion = ctx.global().get::<Companion>().ok_or("missing companion state")?;
        let url = companion.url.lock().map_err(|e| e.to_string())?;
        format!("{url}/decide")
    };
    let in_flight = ctx.global().get::<InFlight>().ok_or("missing in-flight state")?;
    if in_flight.0.swap(true, Ordering::AcqRel) {
        return Ok("busy");
    }

    std::thread::spawn(move || {
        let (func, data) = match post_json(&url, &state).and_then(check_decision) {
            Ok(decision) => ("decision", decision),
            Err(error) => ("error", error),
        };
        // The channel only closes when Arma unloads the extension, so there is nobody left to tell.
        let _ = ctx.callback_data(CALLBACK_NAME, func, data);
        if let Some(in_flight) = ctx.global().get::<InFlight>() {
            in_flight.0.store(false, Ordering::Release);
        }
    });
    Ok("sent")
}

fn post_json(url: &str, body: &str) -> Result<String, String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(REQUEST_TIMEOUT))
        // Never route loopback traffic through a proxy picked up from the environment.
        .proxy(None)
        .build()
        .into();
    let mut response = agent
        .post(url)
        .content_type("application/json")
        .send(body)
        .map_err(|e| format!("companion request failed: {e}"))?;
    response
        .body_mut()
        .read_to_string()
        .map_err(|e| format!("companion reply unreadable: {e}"))
}

fn check_decision(body: String) -> Result<String, String> {
    if body.len() > MAX_DECISION_BYTES {
        return Err(format!("companion reply too large: {} bytes", body.len()));
    }
    serde_json::from_str::<serde_json::Value>(&body)
        .map_err(|e| format!("companion reply is not valid JSON: {e}"))?;
    Ok(body)
}

fn is_loopback_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("http://") else {
        return false;
    };
    let authority = rest.split('/').next().unwrap_or_default();
    let host = match authority.rsplit_once(':') {
        Some((host, port)) if !host.is_empty() && port.parse::<u16>().is_ok() => host,
        _ => authority,
    };
    matches!(host, "127.0.0.1" | "localhost" | "[::1]")
}

#[cfg(test)]
mod tests {
    use super::*;
    use arma_rs::Value;
    use arma_rs::testing::Result as CallbackResult;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    const OK: i32 = 0;
    const APP_ERROR: i32 = 9;

    /// Serves one HTTP request with `reply` as the JSON body and returns the companion URL.
    fn one_shot_companion(reply: &'static str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut buf = [0; 4096];
            loop {
                let n = stream.read(&mut buf).unwrap();
                request.extend_from_slice(&buf[..n]);
                let text = String::from_utf8_lossy(&request);
                let Some(end) = text.find("\r\n\r\n") else { continue };
                let length = text[..end]
                    .lines()
                    .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap()))
                    .unwrap_or(0usize);
                if n == 0 || request.len() >= end + 4 + length {
                    break;
                }
            }
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{reply}",
                reply.len()
            )
            .unwrap();
        });
        url
    }

    /// Arma passes string arguments in SQF string syntax.
    fn quoted(s: &str) -> String {
        format!("\"{}\"", s.replace('"', "\"\""))
    }

    fn wait_for_callback(ext: &arma_rs::testing::Extension) -> CallbackResult<(String, String), String> {
        ext.callback_handler(
            |name, func, data| {
                if name != CALLBACK_NAME {
                    return CallbackResult::Err(format!("unexpected callback name {name}"));
                }
                match data {
                    Some(Value::String(s)) => CallbackResult::Ok((func.to_string(), s)),
                    other => CallbackResult::Err(format!("unexpected data {other:?}")),
                }
            },
            Duration::from_secs(10),
        )
    }

    #[test]
    fn version_matches_crate() {
        let ext = build().testing();
        assert_eq!(ext.call("version", Some(vec![])), (env!("CARGO_PKG_VERSION").to_string(), OK));
    }

    #[test]
    fn loopback_urls() {
        assert!(is_loopback_url("http://127.0.0.1:47800"));
        assert!(is_loopback_url("http://localhost:47800/"));
        assert!(is_loopback_url("http://[::1]:47800"));
        assert!(!is_loopback_url("https://127.0.0.1:47800"));
        assert!(!is_loopback_url("http://example.com:47800"));
        assert!(!is_loopback_url("http://127.0.0.1.example.com"));
    }

    #[test]
    fn set_url_rejects_remote_hosts() {
        let ext = build().testing();
        let (_, code) = ext.call("set_url", Some(vec![quoted("http://example.com")]));
        assert_eq!(code, APP_ERROR);
    }

    #[test]
    fn send_state_rejects_invalid_json() {
        let ext = build().testing();
        let (_, code) = ext.call("send_state", Some(vec![quoted("{not json")]));
        assert_eq!(code, APP_ERROR);
    }

    #[test]
    fn decision_round_trip() {
        let reply = r#"{"action":"wait","reason":"quiet"}"#;
        let ext = build().testing();
        assert_eq!(ext.call("set_url", Some(vec![quoted(&one_shot_companion(reply))])).1, OK);
        assert_eq!(ext.call("send_state", Some(vec![quoted(r#"{"time":1}"#)])), ("sent".to_string(), OK));
        assert_eq!(wait_for_callback(&ext), CallbackResult::Ok(("decision".to_string(), reply.to_string())));
    }

    #[test]
    fn companion_down_reports_error() {
        // Bind then drop a listener to get a port with nothing behind it.
        let port = TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let ext = build().testing();
        assert_eq!(ext.call("set_url", Some(vec![quoted(&format!("http://127.0.0.1:{port}"))])).1, OK);
        assert_eq!(ext.call("send_state", Some(vec![quoted("{}")])).1, OK);
        match wait_for_callback(&ext) {
            CallbackResult::Ok((func, _)) => assert_eq!(func, "error"),
            other => panic!("expected an error callback, got {other:?}"),
        }
    }
}
