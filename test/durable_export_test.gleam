import bankai/durable_export
import bankai/mnesia_store
import bankai/socket
import bankai/sync/jsonl
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const ws = "/tmp/bankai_durable_export"

fn wipe() {
  let _ = simplifile.write(ws <> "/tasks.jsonl", "")
  let _ = simplifile.write(ws <> "/memories.jsonl", "")
  let _ = mnesia_store.init(ws)
  let _ = mnesia_store.reset_workspace_for_test(ws)
  Nil
}

/// A mutation through the daemon request handler leaves the durable export
/// reflecting it: this is the Sep-7-staleness regression. Two creates, both
/// present in tasks.jsonl, marker caught up to the watermark.
pub fn mutation_refreshes_durable_export_test() {
  wipe()
  let _ = socket.handle_request(ws, socket.Request("init", []))
  let _ =
    socket.handle_request(ws, socket.Request("create", ["first pulse task"]))
  let _ =
    socket.handle_request(ws, socket.Request("create", ["second pulse task"]))
  let assert Ok(tasks) = jsonl.load(from: ws <> "/tasks.jsonl")
  tasks
  |> list.any(fn(t) { string.contains(t.title, "first pulse task") })
  |> should.be_true
  tasks
  |> list.any(fn(t) { string.contains(t.title, "second pulse task") })
  |> should.be_true
  let assert Ok(#(exported, watermark)) = durable_export.progress(ws)
  should.equal(exported, watermark)
}

/// A read-only request does not re-export: the marker only moves when the
/// changefeed moves. The response still succeeds with the pulse attached.
pub fn read_only_request_does_not_advance_marker_test() {
  wipe()
  let _ = socket.handle_request(ws, socket.Request("init", []))
  let _ =
    socket.handle_request(ws, socket.Request("create", ["marker anchor task"]))
  let assert Ok(#(exported_before, _)) = durable_export.progress(ws)
  let assert Ok(_) = durable_export.refresh_if_stale(ws)
  case socket.handle_request(ws, socket.Request("list", [])) {
    socket.OkResponse(_) -> {
      let assert Ok(#(exported_after, _)) = durable_export.progress(ws)
      should.equal(exported_before, exported_after)
    }
    socket.ErrorResponse(message) ->
      panic as { "list request failed under the export pulse: " <> message }
  }
}

/// The pulse converges: calling refresh with the feed already caught up
/// succeeds without moving the marker.
pub fn refresh_is_idempotent_when_caught_up_test() {
  wipe()
  let _ = socket.handle_request(ws, socket.Request("init", []))
  let _ = socket.handle_request(ws, socket.Request("create", ["once task"]))
  let assert Ok(_) = durable_export.refresh_if_stale(ws)
  let assert Ok(#(exported, watermark)) = durable_export.progress(ws)
  let assert Ok(_) = durable_export.refresh_if_stale(ws)
  let assert Ok(#(exported_again, watermark_again)) =
    durable_export.progress(ws)
  should.equal(exported, exported_again)
  should.equal(watermark, watermark_again)
}
