//// The update-family router: one grammar, one composed store call.

import bankai/cli/parser
import bankai/daemon_store
import gleam/json
import gleam/list
import gleam/option

pub fn route_update(
  workspace: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  let id = args.id
  // Heartbeat is exclusive and supported: refresh the live claim's lease.
  case args.heartbeat {
    True ->
      case parser.simple_fields_requested(args) {
        False -> daemon_store.heartbeat(workspace, id, args.ttl)
        True -> Error("--heartbeat does not combine with other update fields")
      }
    False -> route_update_rest(workspace, args)
  }
}

fn route_update_rest(
  workspace: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  let id = args.id
  let simple_requested = parser.simple_fields_requested(args)
  let exclusive_count =
    bool_int(args.release)
    + bool_int(args.reopen)
    + bool_int(args.undefer)
    + bool_int(args.satisfy_gate)
    + bool_int(args.close != option.None)
    + bool_int(args.defer_until != option.None)
    + bool_int(args.remove_labels != [])
    + bool_int(args.fence != option.None)
  case exclusive_count, simple_requested {
    0, True ->
      case args.force, args.claim {
        True, option.None -> Error("--force only applies with --claim")
        _, _ -> daemon_store.update_fields(workspace, id, args)
      }
    0, False -> Error("update requires a change")
    1, True ->
      case args.fence, args.status {
        option.Some(fence), option.Some(status) ->
          daemon_store.update_fenced(workspace, id, status, fence)
        _, _ -> Error("only --fence may combine with a status update")
      }
    1, False ->
      case args.fence {
        option.Some(_) -> Error("--fence requires a status")
        option.None -> route_exclusive(workspace, args)
      }
    _, _ ->
      Error(
        "cannot combine lifecycle verbs (--release/--reopen/--undefer/--satisfy-gate/--close/--defer-until/--remove-label/--fence)",
      )
  }
}

fn bool_int(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}

fn route_exclusive(
  workspace: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  let id = args.id
  // Tuple-of-discriminants match: record patterns with `..` would match an
  // empty remove_labels list and shadow the arms below it.
  case
    args.release,
    args.reopen,
    args.undefer,
    args.satisfy_gate,
    args.close,
    args.defer_until,
    args.remove_labels,
    args.fence
  {
    True, _, _, _, _, _, _, _ -> daemon_store.release(workspace, id)
    _, True, _, _, _, _, _, _ -> daemon_store.reopen(workspace, id)
    _, _, True, _, _, _, _, _ -> daemon_store.undefer(workspace, id)
    _, _, _, True, _, _, _, _ -> daemon_store.satisfy_gate(workspace, id)
    _, _, _, _, option.Some(reason), _, _, _ ->
      daemon_store.close(workspace, id, reason)
    _, _, _, _, _, option.Some(until), _, _ ->
      daemon_store.defer_until(workspace, id, until)
    _, _, _, _, _, _, labels, _ ->
      list.fold(labels, Ok(json.null()), fn(acc, l) {
        case acc {
          Ok(_) -> daemon_store.remove_label(workspace, id, l)
          Error(e) -> Error(e)
        }
      })
  }
}
