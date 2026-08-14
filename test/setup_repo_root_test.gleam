//// Regression tests for bk-9a3a: agent directives and git hooks install at
//// the repo root (parent of the .bankai workspace), not inside .bankai.

import bankai/cli
import bankai/cli/setup
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

// --- repo_root derivation ---

pub fn repo_root_strips_dot_bankai_suffix_test() {
  setup.repo_root(".bankai") |> should.equal(".")
  setup.repo_root("./.bankai") |> should.equal(".")
  setup.repo_root("/tmp/bk_repo/.bankai") |> should.equal("/tmp/bk_repo")
  // A workspace that is not a .bankai path is itself the root.
  setup.repo_root("/tmp/bk_plain") |> should.equal("/tmp/bk_plain")
  setup.repo_root("") |> should.equal("")
}

// --- directive lands at repo root, not inside .bankai ---

pub fn setup_writes_directive_at_repo_root_test() {
  let root = "/tmp/bk_setup_rootfix"
  let ws = root <> "/.bankai"
  wipe(ws)
  let _ = simplifile.delete(root <> "/CLAUDE.md")

  let out = cli.run_in(ws, ["setup", "claude"])
  out |> string.contains("wrote " <> root <> "/CLAUDE.md") |> should.be_true

  let directive = simplifile.read(from: root <> "/CLAUDE.md") |> should.be_ok
  directive
  |> string.contains("<!-- BANKAI_INSTRUCTIONS_START -->")
  |> should.be_true

  // Nothing may be written inside the workspace itself.
  simplifile.is_file(ws <> "/CLAUDE.md")
  |> should.be_ok
  |> should.be_false
}

pub fn setup_check_sees_repo_root_directives_test() {
  let root = "/tmp/bk_setup_check_root"
  let ws = root <> "/.bankai"
  wipe(ws)
  let _ = simplifile.delete(root <> "/AGENTS.md")
  let _ = cli.run_in(ws, ["setup", "codex"])

  let check = cli.run_in(ws, ["setup", "check"])
  check |> string.contains("\"agent\":\"codex\"") |> should.be_true
  check |> string.contains("\"configured\":true") |> should.be_true
  check |> string.contains("\"managed_markers\":true") |> should.be_true
}

// --- hooks install at repo root ---

pub fn hooks_install_at_repo_root_test() {
  let root = "/tmp/bk_hooks_root"
  let ws = root <> "/.bankai"
  wipe(ws)
  let out = cli.run_in(ws, ["hooks", "install"])
  out |> string.contains("installed pre-commit hook") |> should.be_true
  let hook =
    simplifile.read(from: root <> "/.git/hooks/pre-commit") |> should.be_ok
  hook |> string.contains("bankai compact") |> should.be_true
}
