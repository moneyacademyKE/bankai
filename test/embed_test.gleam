//// Unit tests for the embed seam: pure resolution logic and the unchanged
//// term-hash backend. No network — ollama reachability is exercised by E2E.

import bankai/embed
import gleam/float
import gleam/list
import gleeunit/should

pub fn resolve_forces_term_hash_test() {
  embed.resolve_from("term-hash", "http://127.0.0.1:1", "unused", Ok(768))
  |> should.equal(embed.TermHash)
}

pub fn resolve_prefers_ollama_when_probe_ok_test() {
  embed.resolve_from(
    "auto",
    "http://localhost:11434",
    "nomic-embed-text",
    Ok(768),
  )
  |> should.equal(embed.Ollama("http://localhost:11434", "nomic-embed-text", 768))
}

pub fn resolve_degrades_to_term_hash_when_probe_fails_test() {
  embed.resolve_from("ollama", "http://127.0.0.1:1", "unused", Error(Nil))
  |> should.equal(embed.TermHash)
}

pub fn term_hash_is_deterministic_normalized_lowercase_test() {
  let a = embed.term_hash("Investigate vehicle fleet telemetry")
  a |> should.equal(embed.term_hash("Investigate vehicle fleet telemetry"))
  // tokenization lowercases, so case must not change the vector
  a |> should.equal(embed.term_hash("INVESTIGATE VEHICLE FLEET TELEMETRY"))
  list.length(a) |> should.equal(embed.dims)
  let sum_of_squares = list.fold(a, 0.0, fn(acc, x) { acc +. x *. x })
  let assert Ok(norm) = float.square_root(sum_of_squares)
  { norm >. 0.999 && norm <. 1.001 } |> should.be_true
}
