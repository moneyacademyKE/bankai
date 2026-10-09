import bankai/cli
import gleam/dynamic/decode
import gleam/json
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

/// bk-e0a0: `ready` orders by (priority asc, created_at asc) — priority must
/// actually influence what surfaces first, not random hex id order.
pub fn ready_orders_by_priority_then_age_test() {
  let ws = "/tmp/bankai_ready_sort"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "low-old", "--priority", "4"])
  let _ = cli.run_in(ws, ["create", "high-new", "--priority", "1"])
  let _ = cli.run_in(ws, ["create", "mid", "--priority", "2"])
  let out = cli.run_in(ws, ["ready"])
  let assert Ok(_) = json.parse(out, decode.dynamic)
  let high_pos = index_of(out, "high-new")
  let mid_pos = index_of(out, "mid")
  let low_pos = index_of(out, "low-old")
  // high-new before mid before low-old, regardless of id assignment order
  { high_pos < mid_pos } |> should.be_true
  { mid_pos < low_pos } |> should.be_true
}

fn index_of(haystack: String, needle: String) -> Int {
  case string.split_once(haystack, needle) {
    Ok(#(before, _)) -> string.length(before)
    Error(_) -> -1
  }
}
