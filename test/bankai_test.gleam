import bankai
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn version_string_test() {
  // bk-e85d: wiring test only — the VALUE is guarded against gleam.toml
  // by version_flag_test.version_constant_matches_gleam_toml_test, so a
  // literal here would just be a second, staler copy of the same fact.
  bankai.version_string()
  |> should.equal(bankai.version)
}

pub fn standalone_sync_reads_are_not_mutations_test() {
  bankai.is_mutation("sync", ["identity"]) |> should.be_false
  bankai.is_mutation("sync", ["conflicts"]) |> should.be_false

  bankai.is_mutation("sync", ["trust", "peer-key"]) |> should.be_true
  bankai.is_mutation("sync", ["revoke", "peer-key"]) |> should.be_true
  bankai.is_mutation("sync", ["rotate", "old-key", "new-key"])
  |> should.be_true
}
