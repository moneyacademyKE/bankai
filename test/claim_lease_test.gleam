import bankai/cli
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  Nil
}

fn task_id(out: String) -> String {
  // cheap extraction: first "id":"bk-..." in the envelope
  let assert Ok(#(_, after)) = string.split_once(out, "\"id\":\"")
  let assert Ok(#(id, _)) = string.split_once(after, "\"")
  id
}

/// bk-ccbf: a claim stamps a live lease on the task.
pub fn claim_sets_lease_test() {
  let ws = "/tmp/bankai_lease_set"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Leased"])
  let id = task_id(created)
  let _ = cli.run_in(ws, ["update", id, "--claim", "agent"])
  let shown = cli.run_in(ws, ["show", id])
  { string.contains(shown, "claim_lease_expires_at\":null") == False }
  |> should.be_true
  string.contains(shown, "claim_lease_expires_at") |> should.be_true
}

/// bk-ccbf: a claim with --ttl 0 expires immediately; reclaim frees it.
pub fn expired_claim_is_reclaimed_test() {
  let ws = "/tmp/bankai_lease_expired"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Dead claim"])
  let id = task_id(created)
  let _ = cli.run_in(ws, ["update", id, "--claim", "agent", "--ttl", "0"])
  let out = cli.run_in(ws, ["reclaim"])
  string.contains(out, id) |> should.be_true
  let shown = cli.run_in(ws, ["show", id])
  string.contains(shown, "\"open\"") |> should.be_true
  string.contains(shown, "\"assignee\":null") |> should.be_true
}

/// bk-ccbf: a live lease is NOT reclaimed.
pub fn live_lease_survives_reclaim_test() {
  let ws = "/tmp/bankai_lease_live"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Alive"])
  let id = task_id(created)
  let _ = cli.run_in(ws, ["update", id, "--claim", "agent"])
  let out = cli.run_in(ws, ["reclaim"])
  { string.contains(out, id) == False } |> should.be_true
  let shown = cli.run_in(ws, ["show", id])
  string.contains(shown, "\"in_progress\"") |> should.be_true
  string.contains(shown, "\"agent\"") |> should.be_true
}

/// bk-ccbf: heartbeat refreshes an expired lease so reclaim leaves it alone.
pub fn heartbeat_refreshes_lease_test() {
  let ws = "/tmp/bankai_lease_heartbeat"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Beating"])
  let id = task_id(created)
  let _ = cli.run_in(ws, ["update", id, "--claim", "agent", "--ttl", "0"])
  let _ = cli.run_in(ws, ["update", id, "--heartbeat"])
  let out = cli.run_in(ws, ["reclaim"])
  { string.contains(out, id) == False } |> should.be_true
  let shown = cli.run_in(ws, ["show", id])
  string.contains(shown, "\"in_progress\"") |> should.be_true
}

/// bk-ccbf: closing a task clears its lease.
pub fn close_clears_lease_test() {
  let ws = "/tmp/bankai_lease_close"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Closing"])
  let id = task_id(created)
  let _ = cli.run_in(ws, ["update", id, "--claim", "agent"])
  let _ = cli.run_in(ws, ["update", id, "closed"])
  let shown = cli.run_in(ws, ["show", id])
  string.contains(shown, "claim_lease_expires_at\":null") |> should.be_true
}
