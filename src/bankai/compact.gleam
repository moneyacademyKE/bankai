//// G5 — memory compaction (Rich-Hickey-compatible: dep-free, no LLM, no datalog).
////
//// Tier + retire: Closed tasks leave the ACTIVE set (so `prime`/load stays
//// bounded and relevant) but move to .bankai/archive.jsonl — still queryable by
//// hash via `inspect`. A summary memory is recorded.
////
//// This is the Letta/Anthropic "core vs archival" pattern (still retrievable,
//// just not in the prompt), NOT lossy LLM summarization — which the
//// consolidation literature (Mem0/Letta/Anthropic/Zero-Mem) explicitly warns
//// against. Summarization is the AGENT's job; bankai is a pure data tool.

import bankai/memory
import bankai/storage/store
import bankai/sync/jsonl
import bankai/time
import bankai/types.{type Task, Closed, Wisp}
import gleam/dict
import gleam/int
import gleam/list
import gleam/set

/// Compact the workspace: move Closed tasks (all their versions) out of the
/// active store into archive.jsonl (deduped by hash), rewrite the active store
/// with what remains, and record a summary memory. Returns a human summary.
pub fn run(workspace: String, tasks_path: String) -> String {
  let index = load_store(tasks_path)
  let closed_ids =
    store.current_tasks(index)
    |> list.filter(fn(t) { t.status == Closed && t.kind != Wisp })
    |> list.map(fn(t) { t.id })
    |> set.from_list

  case set.size(closed_ids) {
    0 -> "nothing to compact (no closed tasks)"
    n -> {
      let all = store.list(index)
      let keep = list.filter(all, fn(t) { !set.contains(closed_ids, t.id) })
      let archived = list.filter(all, fn(t) { set.contains(closed_ids, t.id) })

      // Archive: dedupe by content hash with anything already archived.
      let archive_path = workspace <> "/archive.jsonl"
      let existing = case jsonl.load(from: archive_path) {
        Ok(e) -> e
        Error(_) -> []
      }
      let _ =
        jsonl.flush(dedupe(list.append(existing, archived)), to: archive_path)

      // Rewrite the active store with the survivors.
      let _ = jsonl.flush(keep, to: tasks_path)

      // Record a summary memory (the agent may elaborate; bankai just notes it).
      let note =
        "Compacted "
        <> int.to_string(n)
        <> " closed task(s) retired into archive.jsonl"
      let mem = memory.new(note, time.now())
      let mems = case memory.load(from: workspace <> "/memories.jsonl") {
        Ok(m) -> m
        Error(_) -> []
      }
      let _ = memory.flush([mem, ..mems], to: workspace <> "/memories.jsonl")
      note
    }
  }
}

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}

fn dedupe(tasks: List(Task)) -> List(Task) {
  tasks
  |> list.fold(dict.new(), fn(acc, t) {
    dict.insert(acc, store.hash_key(t.content_hash), t)
  })
  |> dict.values()
}
