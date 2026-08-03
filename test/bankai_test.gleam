import gleeunit
import gleeunit/should
import bankai

pub fn main() {
  gleeunit.main()
}

pub fn version_string_test() {
  bankai.version_string()
  |> should.equal("0.1.0")
}
