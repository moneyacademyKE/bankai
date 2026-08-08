import bankai/cli
import bankai/serde
import bankai/types
import bankai/vector_bridge
import gleam/dynamic/decode
import gleam/json
import gleam/list
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

fn ok_task_decoder() -> decode.Decoder(types.Task) {
  use task <- decode.field("ok", serde.task_decoder())
  decode.success(task)
}

fn task_from_output(output: String) -> Result(types.Task, json.DecodeError) {
  json.parse(from: output, using: ok_task_decoder())
}

/// G10: create --parent produces a hierarchical id "<parent>.<n>", incrementing.
pub fn create_with_parent_gets_hierarchical_id_test() {
  let ws = "/tmp/bankai_phase3_hier"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let parent =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Parent"])))
  let child1 =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["create", "First child", "--parent", parent.id]),
      ),
    )
  child1.id |> should.equal(parent.id <> ".1")
  let child2 =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["create", "Second child", "--parent", parent.id]),
      ),
    )
  child2.id |> should.equal(parent.id <> ".2")
}

/// G10: a missing parent is rejected.
pub fn create_with_missing_parent_errors_test() {
  let ws = "/tmp/bankai_phase3_orphan"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["create", "Orphan", "--parent", "bk-nope"])
  |> string.contains("no such parent")
  |> should.be_true
}

/// G7: setup emits the bankai workflow into the agent-instruction file.
pub fn agent_instructions_describe_workflow_test() {
  let body = cli.agent_instructions()
  body |> string.contains("bankai ready") |> should.be_true
  body |> string.contains("hierarchical") |> should.be_true
  body |> string.contains("remember") |> should.be_true
}

/// Phase 3: backend disclosure is honest and non-empty.
pub fn backend_disclosed_test() {
  vector_bridge.backend() |> string.contains("term-hash") |> should.be_true
}

/// Phase 3: exact-match documents produce a matching result.
pub fn search_finds_exact_match_test() {
  let docs = [
    vector_bridge.Document(
      "task",
      "bk-auth",
      "implement the authentication module",
    ),
    vector_bridge.Document("task", "bk-ui", "redesign the dashboard layout"),
  ]
  let results = vector_bridge.search(docs, "authentication", 0.1, 10)
  list.map(results, fn(r) {
    let vector_bridge.Match(_, id, _) = r
    id
  })
  |> list.contains("bk-auth")
  |> should.be_true
}

/// Phase 3: empty query returns no results regardless of documents.
pub fn search_empty_query_returns_empty_test() {
  let docs = [vector_bridge.Document("task", "bk-1", "anything")]
  vector_bridge.search(docs, "", 0.0, 10) |> should.equal([])
}

/// Phase 3: non-positive limit returns no results.
pub fn search_non_positive_limit_returns_empty_test() {
  let docs = [vector_bridge.Document("task", "bk-1", "anything")]
  vector_bridge.search(docs, "anything", 0.0, 0) |> should.equal([])
}

/// Phase 3: semantic duplicate candidates route returns a JSON ok envelope.
pub fn semantic_duplicates_returns_candidates_test() {
  let ws = "/tmp/bankai_phase3_semantic_dupes"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["create", "Implement authentication module"]),
      ),
    )
  let _ =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["create", "Redesign dashboard layout"])),
    )
  let output = cli.run_in(ws, ["duplicates", "--semantic"])
  string.starts_with(output, "{\"ok\":") |> should.be_true
}

/// Phase 3: prime --query returns a semantic context section.
pub fn prime_query_returns_semantic_context_test() {
  let ws = "/tmp/bankai_phase3_prime_query"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["create", "Authentication module"])),
    )
  let output = cli.run_in(ws, ["prime", "--query", "authentication"])
  output |> string.contains("## Semantic context") |> should.be_true
}

/// Phase 3: prime without --query retains the unaugmented prompt.
pub fn prime_without_query_is_base_prompt_test() {
  let ws = "/tmp/bankai_phase3_prime_noquery"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let base = cli.run_in(ws, ["prime"])
  let with_query = cli.run_in(ws, ["prime", "--query", "topic"])
  with_query |> string.contains("## Semantic context") |> should.be_true
  base |> string.contains("## Semantic context") |> should.be_false
}

/// Phase 3: duplicates without --semantic keeps the explicit-relation response.
pub fn duplicates_backward_compat_test() {
  let ws = "/tmp/bankai_phase3_dupes_compat"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Task A"])))
  let output = cli.run_in(ws, ["duplicates"])
  string.starts_with(output, "{\"ok\":") |> should.be_true
  string.contains(output, "[]") |> should.be_true
}

/// Phase 3: semantic duplicate discovery emits an empty list when no pair qualifies.
pub fn semantic_duplicates_empty_when_no_relations_test() {
  let ws = "/tmp/bankai_phase3_semantic_empty"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Task A"])))
  let _ = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Task B"])))
  let output = cli.run_in(ws, ["duplicates", "--semantic"])
  string.starts_with(output, "{\"ok\":") |> should.be_true
  string.contains(output, "[]") |> should.be_true
}

/// Phase 3: a query without indexed documents states that it found no context.
pub fn prime_query_no_match_returns_no_matches_message_test() {
  let ws = "/tmp/bankai_phase3_prime_nomatch"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let output = cli.run_in(ws, ["prime", "--query", "unrelated topic xyz"])
  output |> string.contains("No matches for:") |> should.be_true
}
