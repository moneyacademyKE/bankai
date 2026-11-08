//// Round-trip regressions for text fields (bk-4e6b / bk-490f): a
//// description or title containing newlines, quotes, backslashes and a
//// brace-leading line (the classic pasted-JSON-error shape) must survive
//// create and update byte-for-byte, a text update must apply rather
//// than refuse, and a same-value text update is an idempotent no-op
//// (the "update requires a change" error belongs to requests that
//// carry no field at all, not to values that happen to repeat).

import bankai/daemon_store
import bankai/mnesia_store
import bankai/storage/store
import gleam/json
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_text_round_trip_test"

const gnarly =
  "para one\n\nLine A before the brace line.\n  {\"error\":\"bankai daemon: create service auth directory: erofs\"}\nLine B after the brace line.\n\nquotes \" and backslash \\ survive too\nTAIL-MARKER-9931"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

/// Create exactly one task with a seed description; return its id.
fn seeded_id() -> String {
  let assert Ok(_json) =
    daemon_store.create(workspace, "Round trip", [
      "--description",
      "seed",
    ])
  let assert Ok(index) = mnesia_store.current_store(workspace)
  let assert [task] = store.list(index)
  task.id
}

pub fn create_description_round_trips_verbatim_test() {
  reset()
  let assert Ok(_json) =
    daemon_store.create(workspace, "Round trip", [
      "--description",
      gnarly,
    ])
  let assert Ok(index) = mnesia_store.current_store(workspace)
  let assert [task] = store.list(index)
  task.description |> should.equal(gnarly)
  // The show path must carry the whole value, not a copy cut at the
  // first quote: that cut is the failure mode bk-4e6b was filed for.
  let assert Ok(shown) = daemon_store.show_task(workspace, task.id)
  let encoded = json.to_string(shown)
  encoded |> string.contains("TAIL-MARKER-9931") |> should.be_true
  encoded |> string.contains("erofs") |> should.be_true
}

pub fn update_description_round_trips_verbatim_test() {
  reset()
  let id = seeded_id()
  let assert Ok(_json) =
    daemon_store.update_fields(
      workspace,
      id,
      option.None,
      option.None,
      False,
      option.None,
      [],
      option.None,
      option.None,
      option.Some(gnarly),
    )
  let assert Ok(task) = mnesia_store.get_current(workspace, id)
  task.description |> should.equal(gnarly)
}

pub fn update_title_round_trips_verbatim_test() {
  reset()
  let id = seeded_id()
  let assert Ok(_json) =
    daemon_store.update_fields(
      workspace,
      id,
      option.None,
      option.None,
      False,
      option.None,
      [],
      option.None,
      option.Some("New title \"quoted\" {braced}"),
      option.None,
    )
  let assert Ok(task) = mnesia_store.get_current(workspace, id)
  task.title |> should.equal("New title \"quoted\" {braced}")
}

pub fn update_same_value_is_an_idempotent_no_op_test() {
  reset()
  let id = seeded_id()
  let assert Ok(_json) =
    daemon_store.update_fields(
      workspace,
      id,
      option.None,
      option.None,
      False,
      option.None,
      [],
      option.None,
      option.None,
      option.Some("seed"),
    )
  let assert Ok(task) = mnesia_store.get_current(workspace, id)
  task.description |> should.equal("seed")
}
