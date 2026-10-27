//// bk-86b0 FIX 1: daemon boot must never wedge inside the vector
//// projection warm. The acceptor awaits the warm worker under a hard
//// deadline; on timeout the worker is killed and boot proceeds to
//// listen with text-search degradation instead of hanging forever.

import bankai/cli
import bankai/socket
import gleam/erlang/process
import gleam/int
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

@external(erlang, "bankai_vector_projection_ffi", "warm_with_deadline")
fn warm_with_deadline(
  workspace: String,
  offset: Int,
  documents: List(#(String, String, String)),
  timeout_ms: Int,
) -> Result(Int, String)

@external(erlang, "erlang", "binary_to_list")
fn charlist(s: String) -> a

@external(erlang, "os", "putenv")
fn putenv_raw(name: a, value: a) -> Bool

@external(erlang, "os", "unsetenv")
fn unsetenv_raw(name: a) -> Bool

// os:putenv/os:unsetenv take charlists, not binaries — passing a Gleam
// string straight through is a badarg (probed directly against OTP).
fn putenv(name: String, value: String) -> Bool {
  putenv_raw(charlist(name), charlist(value))
}

fn unsetenv(name: String) -> Bool {
  unsetenv_raw(charlist(name))
}

fn docs(n: Int) -> List(#(String, String, String)) {
  int.range(1, n + 1, [], fn(acc, i) {
    [
      #(
        "task",
        "bk-warm-" <> int.to_string(i),
        "warm deadline corpus document " <> int.to_string(i),
      ),
      ..acc
    ]
  })
}

/// A warm that cannot finish inside its deadline returns {error, ...}
/// naming the timeout — it must not block the caller indefinitely.
pub fn warm_with_deadline_times_out_instead_of_wedging_test() {
  let ws = "/tmp/bankai_warm_deadline_unit"
  let result = warm_with_deadline(ws, 0, docs(96), 1)
  case result {
    Error(message) -> string.contains(message, "timed out") |> should.be_true
    Ok(_) -> should.be_true(False)
  }
}

/// Killing a wedged worker mid-build must not poison the projection:
/// the acceptor still owns the ETS table, and a later warm on the same
/// workspace succeeds.
pub fn warm_recovers_after_a_killed_worker_test() {
  let ws = "/tmp/bankai_warm_deadline_recovery"
  let _ = warm_with_deadline(ws, 0, docs(96), 1)
  warm_with_deadline(ws, 0, docs(8), 120_000)
  |> should.be_ok
  |> should.equal(8)
}

/// Serve-level contract: when the boot warm exceeds its deadline the
/// daemon prints the skip notice and STILL BINDS THE SOCKET.
pub fn serve_listens_when_warm_times_out_test() {
  let ws = "/tmp/bankai_warm_timeout_serve"
  let _ = cli.run_in(ws, ["init"])
  int.range(1, 61, Nil, fn(_acc, i) {
    let _ =
      socket.handle_request(
        ws,
        socket.Request("create", ["warm serve doc " <> int.to_string(i)]),
      )
    Nil
  })
  let _ = putenv("BANKAI_VECTOR_WARM_TIMEOUT_MS", "1")
  let _ = process.spawn_unlinked(fn() { socket.serve(ws) })
  process.sleep(2500)
  let _ = unsetenv("BANKAI_VECTOR_WARM_TIMEOUT_MS")
  socket.socket_owned(socket.socket_path(ws)) |> should.be_true
}
