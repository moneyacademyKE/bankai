//// Agent setup matrix and Git hooks installation.

import gleam/json
import gleam/list
import gleam/string
import simplifile

pub const bankai_marker_start = "<!-- BANKAI_INSTRUCTIONS_START -->"

pub const bankai_marker_end = "<!-- BANKAI_INSTRUCTIONS_END -->"

pub fn agent_filename(agent: String) -> String {
  case agent {
    "claude" -> "CLAUDE.md"
    "codex" -> "AGENTS.md"
    "cursor" -> ".cursorrules"
    "factory" -> ".factory.md"
    "mux" -> ".mux.md"
    "opencode" -> ".opencode.md"
    "opencrabs" -> ".opencrabs.md"
    "windsurf" -> ".windsurf.md"
    other -> other <> ".md"
  }
}

pub fn inject_instructions(existing: String, instructions: String) -> String {
  let marked_block =
    bankai_marker_start <> "\n" <> instructions <> "\n" <> bankai_marker_end
  case string.contains(existing, bankai_marker_start) {
    True ->
      case string.split_once(existing, bankai_marker_start) {
        Ok(#(before, after_start)) ->
          case string.split_once(after_start, bankai_marker_end) {
            Ok(#(_, after_end)) -> before <> marked_block <> after_end
            Error(_) -> existing <> "\n\n" <> marked_block
          }
        Error(_) -> existing <> "\n\n" <> marked_block
      }
    False ->
      case string.trim(existing) {
        "" -> marked_block
        content -> content <> "\n\n" <> marked_block
      }
  }
}

/// Repo root that owns agent directive files: the parent of the `.bankai`
/// workspace. A workspace that is not a `.bankai` path is itself the root
/// (direct workspace runs, tests).
pub fn repo_root(workspace: String) -> String {
  case workspace {
    ".bankai" -> "."
    _ ->
      case string.split_once(workspace, "/.bankai") {
        Ok(#(root, "")) -> root
        _ -> workspace
      }
  }
}

fn directive_path(workspace: String, filename: String) -> String {
  case repo_root(workspace) {
    "" -> filename
    "." -> filename
    root -> root <> "/" <> filename
  }
}

pub fn setup_cmd(
  workspace: String,
  agent: String,
) -> Result(json.Json, String) {
  let filename = agent_filename(agent)
  let path = directive_path(workspace, filename)
  let existing = case simplifile.read(from: path) {
    Ok(content) -> content
    Error(_) -> ""
  }
  let new_content = inject_instructions(existing, agent_instructions())
  let _ = simplifile.write(new_content, to: path)
  Ok(json.string("wrote " <> path <> " (bankai agent instructions)"))
}

pub fn setup_check_cmd(workspace: String) -> Result(json.Json, String) {
  let agents = [
    "claude", "codex", "cursor", "factory", "mux", "opencode", "opencrabs",
    "windsurf",
  ]
  let statuses =
    agents
    |> list.map(fn(a) {
      let file = directive_path(workspace, agent_filename(a))
      let exists = case simplifile.is_file(file) {
        Ok(b) -> b
        Error(_) -> False
      }
      let has_markers = case exists {
        True ->
          case simplifile.read(from: file) {
            Ok(content) -> string.contains(content, bankai_marker_start)
            Error(_) -> False
          }
        False -> False
      }
      json.object([
        #("agent", json.string(a)),
        #("filename", json.string(agent_filename(a))),
        #("configured", json.bool(exists)),
        #("managed_markers", json.bool(has_markers)),
      ])
    })
  Ok(json.array(statuses, fn(s) { s }))
}

pub fn setup_list_cmd() -> Result(json.Json, String) {
  let agents = [
    "claude", "codex", "cursor", "factory", "mux", "opencode", "opencrabs",
    "windsurf",
  ]
  Ok(json.array(agents, fn(a) { json.string(a) }))
}

pub fn hooks_install_cmd(workspace: String) -> Result(json.Json, String) {
  let hooks_dir = repo_root(workspace) <> "/.git/hooks"
  let hook_path = hooks_dir <> "/pre-commit"
  let hook_content =
    "#!/bin/sh\n# bankai auto-compact hook\nif command -v bankai >/dev/null 2>&1; then\n  bankai compact >/dev/null 2>&1 || true\nfi\n"
  case simplifile.create_directory_all(hooks_dir) {
    Error(_) -> Error("failed to create hooks directory: " <> hooks_dir)
    Ok(_) -> {
      case simplifile.write(hook_content, to: hook_path) {
        Error(_) -> Error("failed to write hook: " <> hook_path)
        Ok(_) ->
          Ok(json.string(
            "installed pre-commit hook at "
            <> hook_path
            <> " (make it executable: chmod +x "
            <> hook_path
            <> ")",
          ))
      }
    }
  }
}

pub fn agent_instructions() -> String {
  "# Working with bankai\n\n"
  <> "bankai is the task-memory mesh for this project. Tasks are content-addressed\n"
  <> "(SHA-256); IDs are short hash prefixes (bk-XXXX), with hierarchical subtask\n"
  <> "IDs of the form bk-XXXX.N.\n\n"
  <> "## Workflow\n"
  <> "1. `bankai ready` — list unblocked tasks; pick one.\n"
  <> "2. `bankai update <id> --claim` — claim it (sets in_progress + assignee).\n"
  <> "3. Do the work; commit atomically per logical change.\n"
  <> "4. `bankai update <id> completed` — mark done.\n"
  <> "5. `bankai dep add <id> <target> [--type blocks]` — wire a dependency (cycle-safe).\n"
  <> "6. `bankai create <title> [--label L].. [--parent <id>] [--priority N]` — new task/subtask.\n"
  <> "7. `bankai remember \"insight\"` — persist a durable note for future runs.\n"
  <> "8. `bankai compact` — retire closed tasks (keeps `prime` bounded).\n"
  <> "9. `bankai prime [--query \"topic\"]` — retrieve relevant context when needed.\n\n"
  <> "All command output is JSON: {\"ok\": ...} / {\"error\": ...}. A `closed` task\n"
  <> "(won't-do) does NOT satisfy a dependency — only `completed` does."
}
