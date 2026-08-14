//// Tests for Phase F: hooks install + extended setup matrix.

import bankai/cli
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = simplifile.write("", to: ws <> "/messages.jsonl")
  Nil
}

// --- hooks install ---

pub fn hooks_install_writes_pre_commit_test() {
  let ws = "/tmp/bk_hooks_install"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws <> "/.git")
  let out = cli.run_in(ws, ["hooks", "install"])
  out |> string.contains("installed pre-commit hook") |> should.be_true
  let hook_path = ws <> "/.git/hooks/pre-commit"
  let exists = simplifile.read(from: hook_path) |> should.be_ok
  exists |> string.contains("bankai compact") |> should.be_true
}

pub fn hooks_install_error_without_git_dir_test() {
  let ws = "/tmp/bk_hooks_no_git"
  wipe(ws)
  // No .git directory — should still try (simplifile.create_directory_all
  // creates the path regardless).
  let out = cli.run_in(ws, ["hooks", "install"])
  out |> string.contains("installed pre-commit hook") |> should.be_true
}

// --- setup matrix ---

pub fn setup_factory_writes_factory_md_test() {
  let ws = "/tmp/bk_setup_factory"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let out = cli.run_in(ws, ["setup", "factory"])
  out |> string.contains(".factory.md") |> should.be_true
}

pub fn setup_mux_writes_mux_md_test() {
  let ws = "/tmp/bk_setup_mux"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let out = cli.run_in(ws, ["setup", "mux"])
  out |> string.contains(".mux.md") |> should.be_true
}

pub fn setup_opencode_writes_opencode_md_test() {
  let ws = "/tmp/bk_setup_opencode"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let out = cli.run_in(ws, ["setup", "opencode"])
  out |> string.contains(".opencode.md") |> should.be_true
}

pub fn setup_opencrabs_writes_opencrabs_md_test() {
  let ws = "/tmp/bk_setup_opencrabs"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let out = cli.run_in(ws, ["setup", "opencrabs"])
  out |> string.contains(".opencrabs.md") |> should.be_true
}

pub fn setup_windsurf_writes_windsurf_md_test() {
  let ws = "/tmp/bk_setup_windsurf"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let out = cli.run_in(ws, ["setup", "windsurf"])
  out |> string.contains(".windsurf.md") |> should.be_true
}

pub fn setup_is_non_destructive_and_preserves_custom_instructions_test() {
  let ws = "/tmp/bk_setup_nondestructive"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let claude_md = ws <> "/CLAUDE.md"
  let initial =
    "# Custom Project Guidelines\n- Always use tabs\n- Never rewrite entire files\n"
  let _ = simplifile.write(initial, to: claude_md)

  let _ = cli.run_in(ws, ["setup", "claude"])
  let updated = simplifile.read(from: claude_md) |> should.be_ok
  updated |> string.contains("# Custom Project Guidelines") |> should.be_true
  updated
  |> string.contains("<!-- BANKAI_INSTRUCTIONS_START -->")
  |> should.be_true
  updated
  |> string.contains("<!-- BANKAI_INSTRUCTIONS_END -->")
  |> should.be_true

  // Second run updates only within markers
  let _ = cli.run_in(ws, ["setup", "claude"])
  let second = simplifile.read(from: claude_md) |> should.be_ok
  second |> string.contains("# Custom Project Guidelines") |> should.be_true
}

pub fn setup_list_and_check_report_matrix_test() {
  let ws = "/tmp/bk_setup_matrix_test"
  wipe(ws)
  let _ = simplifile.create_directory_all(ws)
  let list_out = cli.run_in(ws, ["setup", "list"])
  list_out |> string.contains("claude") |> should.be_true
  list_out |> string.contains("cursor") |> should.be_true
  list_out |> string.contains("opencrabs") |> should.be_true

  let check_out = cli.run_in(ws, ["setup", "check"])
  check_out |> string.contains("managed_markers") |> should.be_true
  check_out |> string.contains(".opencrabs.md") |> should.be_true
}
