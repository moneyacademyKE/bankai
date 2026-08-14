import bankai/claimant
import gleeunit/should

pub fn plain_value_test() {
  claimant.parse(["alice", "--repo", "."])
  |> should.equal("alice")
}

pub fn bare_claim_test() {
  claimant.parse([])
  |> should.equal("agent")
}

pub fn flag_next_test() {
  claimant.parse(["--repo", "."])
  |> should.equal("agent")
}

pub fn single_dash_is_a_name_test() {
  claimant.parse(["sue-1"])
  |> should.equal("sue-1")
}
