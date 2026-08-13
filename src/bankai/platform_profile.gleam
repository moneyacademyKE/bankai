//// Explicit Bankai operating-profile boundary.
////
//// A missing profile means local mode. Cluster mode must be named in this file and
//// is refused by the local daemon entry point until the clustered runtime exists.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import simplifile

pub const filename = "bankai-platform.json"

pub type Mode {
  Local
  Clustered
}

pub type Profile {
  Profile(
    schema_version: Int,
    mode: Mode,
    task_authority: String,
    projection_source: String,
    interchange: String,
    cluster_id: Option(String),
    node_id: Option(String),
  )
}

pub fn default() -> Profile {
  Profile(
    1,
    Local,
    "bankai-mnesia",
    "aarondb-changefeed",
    "jsonl",
    option.None,
    option.None,
  )
}

pub fn path(workspace: String) -> String {
  workspace <> "/.bankai/" <> filename
}

/// Absence selects the backwards-compatible local profile. Invalid explicit
/// configuration is an error; silently guessing a cluster configuration is unsafe.
pub fn load(workspace: String) -> Result(Profile, String) {
  case simplifile.read(from: path(workspace)) {
    Error(_) -> Ok(default())
    Ok(contents) -> from_json(contents)
  }
}

pub fn from_json(contents: String) -> Result(Profile, String) {
  case json.parse(from: contents, using: decoder()) {
    Ok(profile) -> Ok(profile)
    Error(_) -> Error("invalid Bankai platform profile")
  }
}

pub fn to_json(profile: Profile) -> json.Json {
  json.object([
    #("schema_version", json.int(profile.schema_version)),
    #("mode", json.string(mode_name(profile.mode))),
    #("task_authority", json.string(profile.task_authority)),
    #("projection_source", json.string(profile.projection_source)),
    #("interchange", json.string(profile.interchange)),
    #("cluster_id", json.nullable(profile.cluster_id, of: json.string)),
    #("node_id", json.nullable(profile.node_id, of: json.string)),
  ])
}

/// Local `bankai serve` must never silently downgrade an explicit cluster
/// configuration into an independent Mnesia writer.
pub fn require_local_daemon(profile: Profile) -> Result(Nil, String) {
  case profile.mode {
    Local -> Ok(Nil)
    Clustered -> Error("local daemon refused for clustered Bankai profile")
  }
}

pub fn require_clustered_daemon(profile: Profile) -> Result(Nil, String) {
  case profile.mode, profile.cluster_id, profile.node_id {
    Clustered, option.Some(cluster_id), option.Some(node_id)
      if cluster_id != "" && node_id != ""
    -> Ok(Nil)
    Clustered, _, _ -> Error("clustered daemon requires cluster_id and node_id")
    Local, _, _ -> Error("clustered daemon requires a clustered Bankai profile")
  }
}

pub fn mode_name(mode: Mode) -> String {
  case mode {
    Local -> "local"
    Clustered -> "clustered"
  }
}

fn decoder() -> decode.Decoder(Profile) {
  use schema_version <- decode.field("schema_version", decode.int)
  use mode_text <- decode.field("mode", decode.string)
  use task_authority <- decode.field("task_authority", decode.string)
  use projection_source <- decode.field("projection_source", decode.string)
  use interchange <- decode.field("interchange", decode.string)
  use cluster_id <- decode.optional_field(
    "cluster_id",
    option.None,
    decode.optional(decode.string),
  )
  use node_id <- decode.optional_field(
    "node_id",
    option.None,
    decode.optional(decode.string),
  )
  case
    valid_profile(
      schema_version,
      mode_text,
      task_authority,
      projection_source,
      interchange,
      cluster_id,
      node_id,
    )
  {
    Ok(profile) -> decode.success(profile)
    Error(message) -> decode.failure(profile_placeholder(), message)
  }
}

fn valid_profile(
  schema_version: Int,
  mode_text: String,
  task_authority: String,
  projection_source: String,
  interchange: String,
  cluster_id: Option(String),
  node_id: Option(String),
) -> Result(Profile, String) {
  case schema_version != 1 {
    True -> Error("unsupported platform profile schema")
    False ->
      case task_authority, projection_source, interchange {
        "bankai-mnesia", "aarondb-changefeed", "jsonl" ->
          mode_profile(mode_text, cluster_id, node_id)
        _, _, _ -> Error("platform profile violates Bankai authority contract")
      }
  }
}

fn mode_profile(
  mode_text: String,
  cluster_id: Option(String),
  node_id: Option(String),
) -> Result(Profile, String) {
  case mode_text, cluster_id, node_id {
    "local", option.None, option.None -> Ok(default())
    "clustered", option.Some(cluster), option.Some(node)
      if cluster != "" && node != ""
    ->
      Ok(Profile(
        1,
        Clustered,
        "bankai-mnesia",
        "aarondb-changefeed",
        "jsonl",
        option.Some(cluster),
        option.Some(node),
      ))
    "clustered", _, _ ->
      Error("clustered platform profile requires cluster_id and node_id")
    _, _, _ -> Error("unknown platform profile mode")
  }
}

fn profile_placeholder() -> Profile {
  default()
}
