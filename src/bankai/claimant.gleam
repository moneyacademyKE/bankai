//// Claim-assignee extraction for `--claim`.
////
//// The argument immediately after `--claim` is the claimant — unless it is
//// itself a flag (`--repo`, `--label`, ...), in which case the claim is bare
//// and the documented default assignee "agent" applies. A flag is never
//// mistaken for a name (bk-616f).

import gleam/string

/// `["alice", ...] -> "alice"`, `["--repo", "."] -> "agent"`, `[] -> "agent"`.
pub fn parse(args: List(String)) -> String {
  case args {
    [value, ..] ->
      case string.starts_with(value, "--") {
        True -> "agent"
        False -> value
      }
    [] -> "agent"
  }
}
