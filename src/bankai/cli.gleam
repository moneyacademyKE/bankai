//// The bankai CLI — command parser and routing dispatcher.
////
//// Live task operations go through the daemon/Mnesia boundary from the root module.
//// `run_in` remains a pure compatibility seam for legacy fixtures, setup, memory,
//// messages, and compaction; it is never the live task-write authority.

import bankai/cli/conflicts
import bankai/cli/llm
import bankai/cli/maintenance
import bankai/cli/parser
import bankai/cli/setup
import bankai/cli/sync as sync_cli
import bankai/cli/sync_import
import bankai/cli/tasks
import bankai/cli/update
import bankai/version
import gleam/json
import gleam/list
import gleam/result

pub const default_workspace = ".bankai"

/// bk-e85d: machine-readable version envelope for --version/-v, so
/// deployments are verifiable from the binary itself. Mirrors the
/// single-shot envelope contract ({"ok": ...}) used by every other
/// client-facing command; the drift guard lives in
/// test/version_flag_test.gleam.
pub fn version_output() -> String {
  parser.envelope(Ok(json.object([#("version", json.string(version.current))])))
}

/// bk-2d1b: does an argv ask for help? The top-level dispatch and the
/// long-running verbs check this BEFORE booting anything, so `--help`,
/// `bankai help` and `serve --help` answer with usage instead of an
/// "unknown command" envelope or a parked BEAM node.
pub fn wants_help(args: List(String)) -> Bool {
  list.contains(args, "--help")
  || list.contains(args, "-h")
  || list.contains(args, "help")
}

/// Run a command against a workspace. Output is always a JSON envelope:
/// {"ok": <json>} or {"error": "<msg>"}. No-args prints plain help.
pub fn run_in(workspace: String, argv: List(String)) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  case argv {
    [] -> usage()
    ["init", ..] -> parser.envelope(tasks.init_cmd(workspace))
    ["create", ..rest] ->
      case parser.parse_create_args(rest) {
        Error(e) -> parser.envelope(Error(e))
        Ok(parsed) ->
          parser.envelope(tasks.create_cmd(workspace, tasks_path, parsed, rest))
      }
    ["list", ..rest] -> parser.envelope(tasks.list_cmd(tasks_path, rest))
    ["ready", ..rest] -> parser.envelope(tasks.ready_cmd(tasks_path, rest))
    ["count", ..rest] -> parser.envelope(tasks.count_cmd(tasks_path, rest))
    ["blocked", ..rest] -> parser.envelope(tasks.blocked_cmd(tasks_path, rest))
    ["cycles", ..] -> parser.envelope(tasks.cycles_cmd(tasks_path))
    ["duplicates", "--semantic", ..rest] ->
      parser.envelope(maintenance.semantic_duplicates_cmd(tasks_path, rest))
    ["duplicates", ..] -> parser.envelope(tasks.duplicates_cmd(tasks_path))
    ["stale", ..rest] -> parser.envelope(tasks.stale_cmd(tasks_path, rest))
    ["history", id, ..] ->
      parser.envelope(maintenance.history_cmd(tasks_path, id))
    ["analytics", ..] -> parser.envelope(maintenance.analytics_cmd(tasks_path))
    ["search", ..rest] ->
      parser.envelope(maintenance.search_cmd(workspace, tasks_path, rest))
    ["llm", "complete", prompt, ..] -> parser.envelope(llm.complete(prompt))
    ["llm", ..] -> parser.envelope(Error("usage: llm complete <prompt>"))
    ["msg", "add", task_id, text, ..rest] ->
      parser.envelope(tasks.msg_add_cmd(
        workspace,
        tasks_path,
        task_id,
        text,
        rest,
      ))
    ["msg", "list", task_id, ..] ->
      parser.envelope(tasks.msg_list_cmd(workspace, task_id))
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
      parser.envelope(tasks.dep_add_cmd(tasks_path, task_id, target_id, rest))
    ["dep", ..] ->
      parser.envelope(Error("usage: dep add <task-id> <target-id> [--type T]"))
    ["update", ..rest] ->
      case parser.parse_update_args(rest) {
        Error(e) -> parser.envelope(Error(e))
        Ok(parsed) ->
          parser.envelope(update.update_dispatch(tasks_path, parsed))
      }
    ["reclaim", ..] -> parser.envelope(tasks.reclaim_cmd(tasks_path))
    ["remember", text, ..] ->
      parser.envelope(tasks.remember_cmd(workspace, text))
    ["memories", ..] -> parser.envelope(tasks.memories_cmd(workspace))
    ["inspect", hash, ..] ->
      parser.envelope(tasks.inspect_cmd(tasks_path, hash))
    ["prime", "--query", query, ..] ->
      parser.envelope(
        maintenance.prime_query_text(workspace, query)
        |> result.map(json.string),
      )
    ["prime", ..] ->
      parser.envelope(
        maintenance.prime_text(workspace) |> result.map(json.string),
      )
    ["hooks", "install", ..] ->
      parser.envelope(setup.hooks_install_cmd(workspace))
    ["hooks", ..] -> parser.envelope(Error("usage: hooks install"))
    ["setup", "check", ..] -> parser.envelope(setup.setup_check_cmd(workspace))
    ["setup", "list", ..] -> parser.envelope(setup.setup_list_cmd())
    ["setup", agent, ..] -> parser.envelope(setup.setup_cmd(workspace, agent))
    ["compact", ..] ->
      parser.envelope(maintenance.gc_cmd(workspace, tasks_path))
    ["sync", "identity", ..] ->
      parser.envelope(sync_cli.sync_identity_cmd(workspace))
    ["sync", "trust", ..rest] ->
      parser.envelope(sync_cli.sync_trust_cmd(workspace, rest))
    ["sync", "revoke", ..rest] ->
      parser.envelope(sync_cli.sync_revoke_cmd(workspace, rest))
    ["sync", "rotate", ..rest] ->
      parser.envelope(sync_cli.sync_rotate_cmd(workspace, rest))
    ["sync", "conflicts", ..] ->
      parser.envelope(conflicts.sync_conflicts_cmd(workspace))
    ["sync", "resolve", id, ..rest] ->
      parser.envelope(conflicts.sync_resolve_cmd(workspace, id, rest))
    ["sync", "clear", ..] ->
      parser.envelope(conflicts.sync_clear_cmd(workspace))
    ["sync", ..rest] ->
      parser.envelope(sync_import.sync_cmd(workspace, tasks_path, rest))
    ["journal", "tail", ..rest] ->
      parser.envelope(maintenance.journal_tail_cmd(workspace, rest))
    ["journal", ..] ->
      parser.envelope(Error("usage: journal tail [--after <offset>]"))
    ["sync-pull", ..rest] ->
      parser.envelope(sync_import.sync_pull_cmd(workspace, rest))
    [cmd, ..] -> parser.envelope(Error("unknown command: " <> cmd))
  }
}

pub fn error_envelope(message: String) -> String {
  parser.envelope(Error(message))
}

pub fn agent_instructions() -> String {
  setup.agent_instructions()
}

pub fn prime_text(workspace: String) -> Result(String, String) {
  maintenance.prime_text(workspace)
}

pub fn usage() -> String {
  "bankai — content-addressed task memory\n\n"
  <> "usage: bankai <command> [args]\n\n"
  <> "  --version, -v                 print the version (JSON envelope)\n"
  <> "  --help, -h, help              print this usage (no daemon needed)\n"
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
  <> "  update <id> --title T         set the title (new immutable version)\n"
  <> "  update <id> --description D   set the description (new immutable version)\n"
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
  <> "  sync identity                 print this replica's public key\n"
  <> "  sync trust <key> [--expires-at NS]\n"
  <> "                                trust a peer key, optionally until NS\n"
  <> "  sync revoke <key>             revoke a trusted replica key\n"
  <> "  sync rotate <old> <new> [--overlap NS] [--expires-at NS]\n"
  <> "                                rotate trust with a bounded overlap\n"
  <> "  sync-serve [--port N]         serve immutable history + current heads\n"
  <> "  sync-pull --host H [--port N] replicate immutable history from a peer\n"
  <> "  init                          initialize .bankai/\n"
  <> "  serve                         run the daemon (warm JSON-RPC socket path)\n"
  <> "  mcp                           run the MCP stdio server\n\n"
  <> "all command output is a JSON envelope: {\"ok\": ...} / {\"error\": ...}"
}
