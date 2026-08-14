import bankai/cli
import bankai/daemon_store
import bankai/mnesia_store
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_journal_changefeed_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

pub fn journal_tail_returns_ordered_committed_events_test() {
  reset()
  let _ = should.be_ok(daemon_store.boot(workspace))

  let task1 =
    should.be_ok(daemon_store.create(workspace, "First journaled task", []))
  let task2 =
    should.be_ok(daemon_store.create(workspace, "Second journaled task", []))
  let _ = task1
  let _ = task2

  let journal_json = should.be_ok(daemon_store.journal_tail(workspace, -1))
  let journal_str = json.to_string(journal_json)

  journal_str |> string.contains("\"count\":2") |> should.be_true
  journal_str |> string.contains("create") |> should.be_true

  // Tail after offset 0 returns 1 event
  let tail_json = should.be_ok(daemon_store.journal_tail(workspace, 0))
  let tail_str = json.to_string(tail_json)
  tail_str |> string.contains("\"count\":1") |> should.be_true

  // CLI interface works
  let cli_out = cli.run_in(workspace, ["journal", "tail", "--after", "0"])
  cli_out |> string.contains("\"ok\"") |> should.be_true
  cli_out |> string.contains("\"count\":1") |> should.be_true
}
