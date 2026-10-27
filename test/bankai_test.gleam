import bankai
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn version_string_test() {
  bankai.version_string()
  |> should.equal("0.2.0")
}

pub fn standalone_sync_reads_are_not_mutations_test() {
  bankai.is_mutation("sync", ["identity"]) |> should.be_false
  bankai.is_mutation("sync", ["conflicts"]) |> should.be_false

  bankai.is_mutation("sync", ["trust", "peer-key"]) |> should.be_true
  bankai.is_mutation("sync", ["revoke", "peer-key"]) |> should.be_true
  bankai.is_mutation("sync", ["rotate", "old-key", "new-key"])
  |> should.be_true
}
