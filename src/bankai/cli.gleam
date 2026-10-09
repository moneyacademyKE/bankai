//// The bankai CLI — command parser and routing dispatcher.
////
//// Live task operations go through the daemon/Mnesia boundary from the root module.
//// `run_in` remains a pure compatibility seam for legacy fixtures, setup, memory,
//// messages, and compaction; it is never the live task-write authority.

import bankai/builder
import bankai/cli/maintenance
import bankai/cli/parser
import bankai/cli/setup
import bankai/graph
import bankai/memory
import bankai/message
import bankai/relations
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/sync_peer
import bankai/task_view
import bankai/time
import bankai/types.{
  type Task, Blocked, Blocks, Duplicates, InProgress, Open, ParentChild,
  Relationship, Task,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

pub const default_workspace = ".bankai"

/// Run a command against a workspace. Output is always a JSON envelope:
/// {"ok": <json>} or {"error": "<msg>"}. No-args prints plain help.
pub fn run_in(workspace: String, argv: List(String)) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  case argv {
    [] -> usage()
    ["init", ..] -> parser.envelope(init_cmd(workspace))
    ["create", ..rest] ->
      case parser.parse_create_args(rest) {
        Error(e) -> parser.envelope(Error(e))
        Ok(parsed) ->
          parser.envelope(create_cmd(workspace, tasks_path, parsed, rest))
      }
    ["list", ..rest] -> parser.envelope(list_cmd(tasks_path, rest))
    ["ready", ..rest] -> parser.envelope(ready_cmd(tasks_path, rest))
    ["count", ..rest] -> parser.envelope(count_cmd(tasks_path, rest))
    ["blocked", ..rest] -> parser.envelope(blocked_cmd(tasks_path, rest))
    ["cycles", ..] -> parser.envelope(cycles_cmd(tasks_path))
    ["duplicates", "--semantic", ..rest] ->
      parser.envelope(maintenance.semantic_duplicates_cmd(tasks_path, rest))
    ["duplicates", ..] -> parser.envelope(duplicates_cmd(tasks_path))
    ["stale", ..rest] -> parser.envelope(stale_cmd(tasks_path, rest))
    ["history", id, ..] ->
      parser.envelope(maintenance.history_cmd(tasks_path, id))
    ["analytics", ..] -> parser.envelope(maintenance.analytics_cmd(tasks_path))
    ["search", ..rest] ->
      parser.envelope(maintenance.search_cmd(workspace, tasks_path, rest))
    ["msg", "add", task_id, text, ..rest] ->
      parser.envelope(msg_add_cmd(workspace, tasks_path, task_id, text, rest))
    ["msg", "list", task_id, ..] ->
      parser.envelope(msg_list_cmd(workspace, task_id))
    ["msg", ..] ->
      parser.envelope(Error(
        "usage: msg add <task-id> <text> [--reply <msg-id>] | msg list <task-id>",
      ))
    ["backup", "list", ..] ->
      parser.envelope(maintenance.backup_list_cmd(workspace))
    ["backup", "preview", path, ..] ->
      parser.envelope(maintenance.backup_preview_cmd(workspace, path))
    ["backup", "restore", path, ..] ->
      parser.envelope(maintenance.backup_restore_cmd(workspace, path))
    ["backup", "prune", ..rest] ->
      parser.envelope(maintenance.backup_prune_cmd(workspace, rest))
    ["backup", ..] ->
      parser.envelope(maintenance.backup_cmd(workspace, tasks_path))
    ["export", ..rest] ->
      parser.envelope(maintenance.export_cmd(tasks_path, rest))
    ["gc", ..] -> parser.envelope(maintenance.gc_cmd(workspace, tasks_path))
    ["show", id, ..] -> parser.envelope(maintenance.show_cmd(tasks_path, id))
    ["epic", id, ..] -> parser.envelope(maintenance.epic_cmd(tasks_path, id))
    ["dep", "add", task_id, target_id, ..rest] ->
      parser.envelope(dep_add_cmd(tasks_path, task_id, target_id, rest))
    ["dep", ..] ->
      parser.envelope(Error("usage: dep add <task-id> <target-id> [--type T]"))
    ["update", ..rest] ->
      case parser.parse_update_args(rest) {
        Error(e) -> parser.envelope(Error(e))
        Ok(parsed) -> parser.envelope(update_dispatch(tasks_path, parsed))
      }
    ["remember", text, ..] -> parser.envelope(remember_cmd(workspace, text))
    ["memories", ..] -> parser.envelope(memories_cmd(workspace))
    ["inspect", hash, ..] -> parser.envelope(inspect_cmd(tasks_path, hash))
    ["prime", "--query", query, ..] ->
      parser.envelope(
        Ok(json.string(maintenance.prime_query_text(workspace, query))),
      )
    ["prime", ..] ->
      parser.envelope(Ok(json.string(maintenance.prime_text(workspace))))
    ["hooks", "install", ..] ->
      parser.envelope(setup.hooks_install_cmd(workspace))
    ["hooks", ..] -> parser.envelope(Error("usage: hooks install"))
    ["setup", "check", ..] -> parser.envelope(setup.setup_check_cmd(workspace))
    ["setup", "list", ..] -> parser.envelope(setup.setup_list_cmd())
    ["setup", agent, ..] -> parser.envelope(setup.setup_cmd(workspace, agent))
    ["compact", ..] ->
      parser.envelope(maintenance.gc_cmd(workspace, tasks_path))
    ["sync", "conflicts", ..] ->
      parser.envelope(maintenance.sync_conflicts_cmd(workspace))
    ["sync", "resolve", id, ..rest] ->
      parser.envelope(maintenance.sync_resolve_cmd(workspace, id, rest))
    ["sync", "clear", ..] ->
      parser.envelope(maintenance.sync_clear_cmd(workspace))
    ["sync", ..rest] -> parser.envelope(sync_cmd(workspace, tasks_path, rest))
    ["journal", "tail", ..rest] ->
      parser.envelope(maintenance.journal_tail_cmd(workspace, rest))
    ["journal", ..] ->
      parser.envelope(Error("usage: journal tail [--after <offset>]"))
    ["sync-pull", ..rest] -> parser.envelope(sync_pull_cmd(workspace, rest))
    [cmd, ..] -> parser.envelope(Error("unknown command: " <> cmd))
  }
}

pub fn error_envelope(message: String) -> String {
  parser.envelope(Error(message))
}

pub fn agent_instructions() -> String {
  setup.agent_instructions()
}

pub fn prime_text(workspace: String) -> String {
  maintenance.prime_text(workspace)
}

fn init_cmd(workspace: String) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  Ok(json.string("initialized bankai workspace at " <> workspace))
}

fn create_cmd(
  workspace: String,
  tasks_path: String,
  parsed: parser.CreateArgs,
  _raw_rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  let now = time.now()
  let parser.CreateArgs(
    title,
    description,
    labels,
    priority_text,
    parent,
    kind_text,
  ) = parsed
  let priority = case priority_text {
    option.Some(p) -> parser.parse_priority(["--priority", p])
    option.None -> 1
  }
  let kind = case kind_text {
    option.Some(k) -> parser.parse_kind(["--kind", k])
    option.None -> types.DefaultTask
  }
  case parent {
    option.Some(parent_id) -> {
      let index = load_store(tasks_path)
      case store.find_by_id(index, parent_id) {
        Error(Nil) -> Error("no such parent task: " <> parent_id)
        Ok(_) -> {
          case
            graph.would_cycle_parent_chain(
              store.current_tasks(index),
              parent_id <> ".__probe__",
              parent_id,
            )
          {
            True ->
              Error(
                "parent relation would create a hierarchy cycle: " <> parent_id,
              )
            False -> {
              let id = next_child_id(index, parent_id)
              let rels = [
                Relationship(target_id: parent_id, relation: ParentChild),
              ]
              let task =
                builder.build_full(
                  id,
                  title,
                  description,
                  Open,
                  option.None,
                  priority,
                  now,
                  now,
                  rels,
                  labels,
                  option.Some(parent_id),
                  kind,
                )
              let index = store.put(index, task)
              let _ = jsonl.flush(store.list(index), to: tasks_path)
              Ok(serde.task_to_json(task))
            }
          }
        }
      }
    }
    option.None -> {
      let task =
        builder.build_with_derived_id(
          title,
          description,
          Open,
          option.None,
          priority,
          now,
          now,
          [],
          labels,
          option.None,
          kind,
        )
      let index = store.put(load_store(tasks_path), task)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(task))
    }
  }
}

/// Same envelope as the daemon path (task_view) so scripts see ONE list
/// shape whether the daemon answered or this process read the store itself.
fn list_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case task_view.parse(rest) {
    Error(e) -> Error(e)
    Ok(spec) -> {
      let tasks = load_store(tasks_path) |> store.current_tasks()
      Ok(task_view.envelope(
        tasks,
        spec,
        time.now(),
        task_view.has_flag(rest, "--compact"),
      ))
    }
  }
}

fn ready_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> graph.ready_tasks()
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

fn count_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks = load_store(tasks_path) |> store.current_tasks()
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.object([#("count", json.int(list.length(tasks)))]))
}

fn blocked_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.filter(fn(t) { t.status == Blocked })
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

fn cycles_cmd(tasks_path: String) -> Result(json.Json, String) {
  let edges =
    load_store(tasks_path)
    |> store.current_tasks()
    |> graph.cycle_edges()
  Ok(
    json.array(edges, of: fn(e) {
      let #(from, to) = e
      json.object([
        #("from", json.string(from)),
        #("to", json.string(to)),
      ])
    }),
  )
}

fn duplicates_cmd(tasks_path: String) -> Result(json.Json, String) {
  let pairs =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.flat_map(fn(t) {
      t.relationships
      |> list.filter(fn(r) { r.relation == Duplicates })
      |> list.map(fn(r) { #(t.id, r.target_id) })
    })
  Ok(
    json.array(pairs, of: fn(p) {
      let #(a, b) = p
      json.object([
        #("a", json.string(a)),
        #("b", json.string(b)),
      ])
    }),
  )
}

fn stale_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let days = parser.parse_days(rest)
  let cutoff = time.now() - days * time.day_ns
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.filter(fn(t) { graph.is_active(t.status) && t.updated_at < cutoff })
  Ok(json.array(tasks, of: serde.task_to_json))
}

fn msg_add_cmd(
  workspace: String,
  tasks_path: String,
  task_id: String,
  text: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  case store.find_by_id(load_store(tasks_path), task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(_) -> {
      let parent = msg_add_parse_reply(rest)
      let msg = message.new(task_id, parent, "agent", text, time.now())
      let path = workspace <> "/messages.jsonl"
      let existing = case message.load(from: path) {
        Ok(m) -> m
        Error(_) -> []
      }
      let _ = message.flush([msg, ..existing], to: path)
      Ok(message.message_to_json(msg))
    }
  }
}

fn msg_list_cmd(
  workspace: String,
  task_id: String,
) -> Result(json.Json, String) {
  let path = workspace <> "/messages.jsonl"
  let msgs = case message.load(from: path) {
    Ok(m) -> m
    Error(_) -> []
  }
  let task_msgs =
    msgs
    |> list.filter(fn(m) { m.task_id == task_id })
    |> list.sort(fn(a, b) { int.compare(b.ts, a.ts) })
  Ok(json.array(task_msgs, of: message.message_to_json))
}

fn dep_add_cmd(
  tasks_path: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let rel_type = parser.parse_relation_type(rest)
  let index = load_store(tasks_path)
  case store.find_by_id(index, task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(task) ->
      case store.find_by_id(index, target_id) {
        Error(Nil) -> Error("no such task: " <> target_id)
        Ok(_) -> {
          let cycle =
            graph.would_cycle(graph.all_edges(store.current_tasks(index)), #(
              task_id,
              target_id,
            ))
          case rel_type, cycle {
            Blocks, True ->
              Error(
                "relation would create a cycle: "
                <> task_id
                <> " -> "
                <> target_id,
              )
            _, _ -> {
              let updated =
                relations.relation_typed(task, target_id, rel_type, time.now())
              let index = store.put(index, updated)
              let _ = jsonl.flush(store.list(index), to: tasks_path)
              Ok(serde.task_to_json(updated))
            }
          }
        }
      }
  }
}

/// One update, one write (bk-57c1): the parsed grammar composes status,
/// claim, labels and priority in a single task rewrite instead of per-flag
/// arms that silently swallowed each other's args.
fn update_dispatch(
  tasks_path: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  // Daemon-only lifecycle verbs fail loudly here rather than being ignored.
  case
    args.release
    || args.reopen
    || args.undefer
    || args.satisfy_gate
    || args.close != option.None
    || args.defer_until != option.None
    || args.fence != option.None
    || args.remove_labels != []
  {
    True ->
      Error(
        "that update verb requires the bankai daemon (start it with `bankai serve`)",
      )
    False -> apply_update(tasks_path, args)
  }
}

fn apply_update(
  tasks_path: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  let new_status = case args.status {
    option.None -> Ok(option.None)
    option.Some(s) ->
      case serde.status_from_string(s) {
        Ok(parsed) -> Ok(option.Some(parsed))
        Error(Nil) -> Error("invalid status: " <> s)
      }
  }
  use new_status <- result.try(new_status)
  let new_priority = case args.priority {
    option.None -> Ok(option.None)
    option.Some(p) ->
      case int.parse(p) {
        Ok(parsed) -> Ok(option.Some(parsed))
        Error(_) -> Error("invalid priority: " <> p)
      }
  }
  use new_priority <- result.try(new_priority)
  // --force is only meaningful alongside --claim.
  use Nil <- result.try(case args.force, args.claim {
    True, option.None -> Error("--force only applies with --claim")
    _, _ -> Ok(Nil)
  })
  let index = load_store(tasks_path)
  case store.find_by_id(index, args.id) {
    Error(Nil) -> Error("no such task: " <> args.id)
    Ok(task) -> {
      // Claim guards (bk-9f48): only Open/InProgress tasks are claimable,
      // and a task owned by someone else needs --force to reclaim. Loud
      // beats clever: a silent steal corrupts the ledger.
      let claim_error = case args.claim {
        option.None -> option.None
        option.Some(new_claimant) ->
          case task.status {
            Open | InProgress ->
              case task.assignee, args.force {
                option.Some(owner), False ->
                  case owner == new_claimant {
                    True -> option.None
                    False ->
                      option.Some(
                        "already claimed by "
                        <> owner
                        <> " (use --force to reclaim)",
                      )
                  }
                _, _ -> option.None
              }
            _ -> option.Some("task is not open: " <> args.id)
          }
      }
      case claim_error {
        option.Some(message) -> Error(message)
        option.None ->
          apply_guarded_update(
            tasks_path,
            index,
            task,
            args,
            new_status,
            new_priority,
          )
      }
    }
  }
}

fn apply_guarded_update(
  tasks_path: String,
  index: store.Store,
  task: Task,
  args: parser.UpdateArgs,
  new_status: option.Option(types.TaskStatus),
  new_priority: option.Option(Int),
) -> Result(json.Json, String) {
  // Idempotency: a no-op update must leave the task (and its content
  // hash) byte-identical — no updated_at bump, matching the old
  // per-flag handlers that returned the task unchanged.
  let effective_status = case new_status, args.claim {
    option.Some(s), _ -> option.Some(s)
    // Claim implies in_progress when no explicit status was given:
    // one claim semantic on every path (bk-9f48 groundwork).
    option.None, option.Some(_) -> option.Some(InProgress)
    option.None, option.None -> option.None
  }
  let added_labels =
    list.filter(args.labels, fn(l) { !list.contains(task.labels, l) })
  let changed =
    added_labels != []
    || case args.claim {
      option.None -> False
      option.Some(a) -> task.assignee != option.Some(a)
    }
    || case new_priority {
      option.None -> False
      option.Some(p) -> task.priority != p
    }
    || case effective_status {
      option.None -> False
      option.Some(s) -> task.status != s
    }
  case changed {
    False -> Ok(serde.task_to_json(task))
    True -> {
      let updated =
        builder.update(task, fn(t) {
          let t = case added_labels {
            [] -> t
            new -> Task(..t, labels: list.append(new, t.labels))
          }
          let t = case args.claim {
            option.None -> t
            option.Some(assignee) -> Task(..t, assignee: option.Some(assignee))
          }
          let t = case new_priority {
            option.None -> t
            option.Some(p) -> Task(..t, priority: p)
          }
          let t = case effective_status {
            option.None -> t
            option.Some(s) -> Task(..t, status: s)
          }
          Task(..t, updated_at: time.now())
        })
      let index = store.put(index, updated)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(updated))
    }
  }
}

fn remember_cmd(workspace: String, text: String) -> Result(json.Json, String) {
  memory.remember(workspace, text) |> result.map(memory.memory_to_json)
}

fn memories_cmd(workspace: String) -> Result(json.Json, String) {
  memory.all(workspace)
  |> result.map(fn(memories) { json.array(memories, of: memory.memory_to_json) })
}

fn inspect_cmd(tasks_path: String, hash: String) -> Result(json.Json, String) {
  case store.get_by_hex(load_store(tasks_path), hash) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no task for hash: " <> hash)
  }
}

fn sync_cmd(
  workspace: String,
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case parse_peers(rest) {
    option.Some(peers_file) -> {
      case simplifile.read(from: peers_file) {
        Error(_) -> Error("could not read peers file: " <> peers_file)
        Ok(contents) -> {
          let peers =
            contents
            |> string.split("\n")
            |> list.filter(fn(line) { line != "" })
          let reports =
            list.fold(peers, [], fn(reports, peer_line) {
              let host_port = string.split(peer_line, ":")
              case host_port {
                [host, port_str, ..] -> {
                  case int.parse(port_str) {
                    Ok(port) -> {
                      case sync_peer.fetch(host, port, workspace) {
                        Error(msg) -> [
                          #("error", host <> ":" <> port_str, msg),
                          ..reports
                        ]
                        Ok(snapshot) -> [
                          #(
                            "fetched",
                            host <> ":" <> port_str,
                            int.to_string(list.length(snapshot.versions)),
                          ),
                          ..reports
                        ]
                      }
                    }
                    Error(_) -> [
                      #("error", peer_line, "invalid port"),
                      ..reports
                    ]
                  }
                }
                _ -> [
                  #("error", peer_line, "invalid host:port format"),
                  ..reports
                ]
              }
            })
          let report_lines =
            reports
            |> list.map(fn(r) {
              let #(kind, peer, msg) = r
              case kind {
                "fetched" -> "fetched " <> msg <> " task(s) from " <> peer
                "error" -> "error from " <> peer <> ": " <> msg
                _ -> peer <> ": " <> msg
              }
            })
          Ok(json.string(string.join(report_lines, "\n")))
        }
      }
    }
    option.None -> {
      case parser.parse_from(rest) {
        option.Some(remote_path) -> {
          let local = store.list(load_store(tasks_path))
          case jsonl.load(from: remote_path) {
            Error(_) -> Error("could not read remote: " <> remote_path)
            Ok(remote_tasks) -> {
              let result = merge.merge(local, remote_tasks)
              let _ = jsonl.flush(result.tasks, to: tasks_path)
              let recorded =
                maintenance.record_merge_conflicts(workspace, result.conflicts)
              let nc = list.length(result.conflicts)
              let base =
                "merged "
                <> int.to_string(list.length(result.tasks))
                <> " task(s)"
              Ok(
                json.string(case nc {
                  0 -> base
                  _ ->
                    case recorded {
                      [] ->
                        base
                        <> " ("
                        <> int.to_string(nc)
                        <> " conflict(s) already recorded — run 'sync conflicts')"
                      _ ->
                        base
                        <> " ("
                        <> int.to_string(nc)
                        <> " conflict(s): "
                        <> string.join(recorded, ", ")
                        <> " — run 'sync conflicts')"
                    }
                }),
              )
            }
          }
        }
        option.None -> {
          let tasks = store.list(load_store(tasks_path))
          let _ = jsonl.flush(tasks, to: tasks_path)
          Ok(json.string(
            "synced " <> int.to_string(list.length(tasks)) <> " task(s)",
          ))
        }
      }
    }
  }
}

fn sync_pull_cmd(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let host = parse_host(rest)
  let port = sync_peer.parse_port(rest, sync_peer.default_port)
  sync_peer.fetch(host, port, workspace)
  |> result.map(fn(snapshot) {
    json.string(
      "fetched "
      <> int.to_string(list.length(snapshot.versions))
      <> " immutable version(s) and "
      <> int.to_string(list.length(snapshot.heads))
      <> " head(s) from "
      <> host
      <> ":"
      <> int.to_string(port)
      <> "; import requires the daemon",
    )
  })
}

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}

fn parse_peers(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--peers", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_peers(rest)
  }
}

fn parse_host(args: List(String)) -> String {
  case args {
    ["--host", v, ..] -> v
    [_, ..rest] -> parse_host(rest)
    [] -> "localhost"
  }
}

fn msg_add_parse_reply(args: List(String)) -> String {
  case args {
    ["--reply", v, ..] -> v
    [_, ..rest] -> msg_add_parse_reply(rest)
    [] -> ""
  }
}

fn next_child_id(index: store.Store, parent_id: String) -> String {
  let prefix = parent_id <> "."
  let nums =
    store.current_tasks(index)
    |> list.filter_map(fn(t) {
      case string.starts_with(t.id, prefix) {
        False -> Error(Nil)
        True -> {
          let prefix_len = string.length(prefix)
          let suffix =
            string.slice(t.id, prefix_len, string.length(t.id) - prefix_len)
          case int.parse(suffix) {
            Ok(n) -> Ok(n)
            Error(Nil) -> Error(Nil)
          }
        }
      }
    })
  let next = case list.max(nums, with: int.compare) {
    Ok(m) -> m + 1
    Error(Nil) -> 1
  }
  parent_id <> "." <> int.to_string(next)
}

fn filter_by_label(tasks: List(Task), label: Option(String)) -> List(Task) {
  case label {
    option.None -> tasks
    option.Some(l) -> list.filter(tasks, fn(t) { list.contains(t.labels, l) })
  }
}

pub fn usage() -> String {
  "bankai — content-addressed task memory\n\n"
  <> "usage: bankai <command> [args]\n\n"
  <> "  create <title> [--label L].. [--parent <id>] [--priority N]\n"
  <> "                                create a task / subtask\n"
  <> "  show <id>                     print a task by id (JSON)\n"
  <> "  epic <id>                     roll up a parent's hierarchical children\n"
  <> "  list [--label L]              list current tasks (JSON array)\n"
  <> "  ready [--label L]             list unblocked tasks (JSON array)\n"
  <> "  count [--label L]             count current tasks\n"
  <> "  blocked [--label L]           list blocked tasks (JSON array)\n"
  <> "  cycles                        report dependency edges on a cycle\n"
  <> "  duplicates                    list task pairs linked by Duplicates\n"
  <> "  duplicates --semantic [--threshold N]\n"
  <> "                                list similarity candidates (review only)\n"
  <> "  stale [--days N]              active tasks not updated in N days (drift)\n"
  <> "  history <id>                  status timeline for a task (aarondb)\n"
  <> "  analytics                     counts by status + avg cycle time (aarondb)\n"
  <> "  search <query>                full-text search across tasks/memories (BM25)\n"
  <> "  msg list <task-id>            list messages for a task (newest first)\n"
  <> "  msg add <task-id> <text> [--reply <msg-id>]\n"
  <> "                                post a threaded message\n"
  <> "  msg list <task-id>            list messages for a task (newest first)\n"
  <> "  backup                        copy tasks.jsonl to a timestamped .bak\n"
  <> "  export [--format md|json]     render tasks as checklist or JSON\n"
  <> "  gc                            retire closed tasks into archive.jsonl\n"
  <> "  dep add|remove|list|tree|graph|check ...\n"
  <> "                                inspect and mutate typed relations\n"
  <> "  update <id> <status>          open|in_progress|blocked|completed|closed\n"
  <> "  update <id> --claim [a]       claim: in_progress + assignee (default agent)\n"
  <> "  update <id> --release         unclaim and return in_progress work to open\n"
  <> "  update <id> --reopen          reopen completed or closed work\n"
  <> "  update <id> --defer-until N   hide from ready until unix timestamp N\n"
  <> "  update <id> --undefer         clear task deferral\n"
  <> "  update <id> --label L         add a label\n"
  <> "  update <id> --remove-label L  remove a label\n"
  <> "  update <id> --priority N      set the priority\n"
  <> "  batch --idempotency-key K <mutation>...\n"
  <> "                                atomically apply one mutation per task\n"
  <> "  auth mint <read|write|admin> [--ttl seconds]\n"
  <> "                                mint signed service capability (admin only)\n"
  <> "  rule register <name> <source>  register unapproved durable rule source\n"
  <> "  rule list|show|approve|revoke|eval|audit  manage locally approved rules\n"
  <> "  remember \"insight\"            persist a content-addressed memory\n"
  <> "  memories                      list persisted memories\n"
  <> "  inspect <hash>                render the task for a content hash\n"
  <> "  compact                       retire closed tasks into archive.jsonl\n"
  <> "  prime [--query <text>]       emit agent prompt, optionally with relevant context\n"
  <> "  setup <claude|codex|cursor|factory|mux|opencode|opencrabs|windsurf>\n"
  <> "                                write agent-instruction file\n"
  <> "  sync [--from <path>]          import a portable JSONL snapshot\n"
  <> "  sync --peers <file>           replicate immutable history from peers\n"
  <> "  sync conflicts                list recorded merge conflicts\n"
  <> "  sync resolve <id> --keep local|remote\n"
  <> "                                resolve a merge conflict by picking a side\n"
  <> "  sync clear                    drop all pending conflict records\n"
  <> "  sync-serve [--port N]         serve immutable history + current heads\n"
  <> "  sync-pull --host H [--port N] replicate immutable history from a peer\n"
  <> "  init                          initialize .bankai/\n"
  <> "  serve                         run the daemon (warm JSON-RPC socket path)\n\n"
  <> "all command output is a JSON envelope: {\"ok\": ...} / {\"error\": ...}"
}
