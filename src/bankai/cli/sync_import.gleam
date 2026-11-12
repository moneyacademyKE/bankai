//// File and peer sync commands: sync --from, sync --peers, sync-pull.

import bankai/cli/conflicts
import bankai/cli/parser
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/sync_peer
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

pub fn sync_cmd(
  workspace: String,
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case parse_peers(rest) {
    option.Some(peers_file) -> {
      case simplifile.read(from: peers_file) {
        Error(_) -> Error("could not read peers file: " <> peers_file)
        Ok(contents) -> {
          let peers =
            contents
            |> string.split("\n")
            |> list.filter(fn(line) { line != "" })
          let reports =
            list.fold(peers, [], fn(reports, peer_line) {
              let host_port = string.split(peer_line, ":")
              case host_port {
                [host, port_str, ..] -> {
                  case int.parse(port_str) {
                    Ok(port) -> {
                      case sync_peer.fetch(host, port, workspace) {
                        Error(msg) -> [
                          #("error", host <> ":" <> port_str, msg),
                          ..reports
                        ]
                        Ok(snapshot) -> [
                          #(
                            "fetched",
                            host <> ":" <> port_str,
                            int.to_string(list.length(snapshot.versions)),
                          ),
                          ..reports
                        ]
                      }
                    }
                    Error(_) -> [
                      #("error", peer_line, "invalid port"),
                      ..reports
                    ]
                  }
                }
                _ -> [
                  #("error", peer_line, "invalid host:port format"),
                  ..reports
                ]
              }
            })
          let report_lines =
            reports
            |> list.map(fn(r) {
              let #(kind, peer, msg) = r
              case kind {
                "fetched" -> "fetched " <> msg <> " task(s) from " <> peer
                "error" -> "error from " <> peer <> ": " <> msg
                _ -> peer <> ": " <> msg
              }
            })
          Ok(json.string(string.join(report_lines, "\n")))
        }
      }
    }
    option.None -> {
      case parser.parse_from(rest) {
        option.Some(remote_path) -> {
          use index <- result.try(jsonl.load_store(from: tasks_path))
          let local = store.list(index)
          case jsonl.load(from: remote_path) {
            Error(_) -> Error("could not read remote: " <> remote_path)
            Ok(remote_tasks) -> {
              let result = merge.merge(local, remote_tasks)
              use _ <- result.try(jsonl.flush_report(
                result.tasks,
                to: tasks_path,
              ))
              let recorded =
                conflicts.record_merge_conflicts(workspace, result.conflicts)
              let nc = list.length(result.conflicts)
              let base =
                "merged "
                <> int.to_string(list.length(result.tasks))
                <> " task(s)"
              Ok(
                json.string(case nc {
                  0 -> base
                  _ ->
                    case recorded {
                      [] ->
                        base
                        <> " ("
                        <> int.to_string(nc)
                        <> " conflict(s) already recorded — run 'sync conflicts')"
                      _ ->
                        base
                        <> " ("
                        <> int.to_string(nc)
                        <> " conflict(s): "
                        <> string.join(recorded, ", ")
                        <> " — run 'sync conflicts')"
                    }
                }),
              )
            }
          }
        }
        option.None -> {
          use index <- result.try(jsonl.load_store(from: tasks_path))
          let tasks = store.list(index)
          use _ <- result.try(jsonl.flush_report(tasks, to: tasks_path))
          Ok(json.string(
            "synced " <> int.to_string(list.length(tasks)) <> " task(s)",
          ))
        }
      }
    }
  }
}

pub fn sync_pull_cmd(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let host = parse_host(rest)
  let port = sync_peer.parse_port(rest, sync_peer.default_port)
  sync_peer.fetch(host, port, workspace)
  |> result.map(fn(snapshot) {
    json.string(
      "fetched "
      <> int.to_string(list.length(snapshot.versions))
      <> " immutable version(s) and "
      <> int.to_string(list.length(snapshot.heads))
      <> " head(s) from "
      <> host
      <> ":"
      <> int.to_string(port)
      <> "; import requires the daemon",
    )
  })
}

pub fn parse_peers(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--peers", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_peers(rest)
  }
}

pub fn parse_host(args: List(String)) -> String {
  case args {
    ["--host", v, ..] -> v
    [_, ..rest] -> parse_host(rest)
    [] -> "localhost"
  }
}
