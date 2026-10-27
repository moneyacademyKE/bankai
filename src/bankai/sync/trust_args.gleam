//// Shared argument grammar for trust commands on every external transport.

import bankai/sync/trust
import gleam/int

pub fn expiry_args(args: List(String)) -> Result(Int, String) {
  expiry_args_at(args, trust.no_expiry)
}

fn expiry_args_at(args: List(String), expiry: Int) -> Result(Int, String) {
  case args {
    [] -> Ok(expiry)
    ["--expires-at", value, ..rest] ->
      case int.parse(value) {
        Ok(value) -> expiry_args_at(rest, value)
        Error(_) -> Error("expires-at must be an integer nanosecond timestamp")
      }
    _ -> Error("usage: sync trust <public-key> [--expires-at NS]")
  }
}

pub fn rotation_args(args: List(String)) -> Result(#(Int, Int), String) {
  rotation_args_at(args, 0, trust.no_expiry)
}

fn rotation_args_at(
  args: List(String),
  overlap: Int,
  expires_at: Int,
) -> Result(#(Int, Int), String) {
  case args {
    [] -> Ok(#(overlap, expires_at))
    ["--overlap", value, ..rest] ->
      case int.parse(value) {
        Ok(value) -> rotation_args_at(rest, value, expires_at)
        Error(_) -> Error("overlap must be a non-negative integer")
      }
    ["--expires-at", value, ..rest] ->
      case int.parse(value) {
        Ok(value) -> rotation_args_at(rest, overlap, value)
        Error(_) -> Error("expires-at must be an integer nanosecond timestamp")
      }
    _ ->
      Error(
        "usage: sync rotate <old-key> <new-key> [--overlap NS] [--expires-at NS]",
      )
  }
}
