//// bk-e85d: a --version/-v flag so deployments are verifiable from the
//// binary itself, plus a drift guard keeping `version.current` honest
//// against gleam.toml. The constant had already drifted (0.2.0 vs 0.4.0)
//// when this test was written — that drift is the first red run.

import bankai/cli
import bankai/version
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

/// The flag's output is a machine-readable envelope carrying the same
/// constant the MCP surface reports, so clients can diff versions
/// without scraping usage text.
pub fn version_output_envelope_test() {
  let assert Ok(value) =
    json.parse(
      cli.version_output(),
      decode.at(["ok", "version"], decode.string),
    )
  should.equal(value, version.current)
}

/// Drift guard: `version.current` must equal the package version
/// declared in gleam.toml. Red the moment someone bumps one without
/// the other.
pub fn version_constant_matches_gleam_toml_test() {
  let assert Ok(toml) = simplifile.read("./gleam.toml")
  let declared =
    toml
    |> string.split("\n")
    |> list.find(fn(line) { string.starts_with(line, "version = ") })
    |> result.map(extract_version)
    |> result.unwrap("<no version line in gleam.toml>")
  should.equal(declared, version.current)
}

fn extract_version(line: String) -> String {
  line
  |> string.replace("version = ", "")
  |> string.replace("\"", "")
  |> string.trim
}
