//// MCP tool catalog. Data only: names and descriptions the protocol serves.
//// Kept out of mcp.gleam so the protocol file stays under the size ceiling.

import gleam/json

// --- tool catalog ---

pub fn tools() -> List(json.Json) {
  [
    tool(
      "ready",
      "Query readiness or explanations with shared filters/sort/page options. Add --explain for data-shaped reasons or --claim to atomically claim.",
    ),
    tool(
      "list",
      "Query current tasks with status/kind/priority/assignee/label/date/sort/page filters; --compact selects a brief projection.",
    ),
    tool("count", "Count tasks matching the same structured query options."),
    tool("blocked", "Query blocked tasks with the same structured options."),
    tool("show", "Show a task by id. args: [\"bk-xxxx\"]."),
    tool(
      "create",
      "Create a task. args: [\"title\", \"--label\", \"L\", \"--description\", \"D\"].",
    ),
    tool(
      "update",
      "Update lifecycle: status, claim, release, reopen, defer/undefer, add/remove label, priority.",
    ),
    tool(
      "batch",
      "Atomically apply one mutation per task. args: [\"--idempotency-key\", \"key\", \"release:bk-a\", \"priority:bk-b:5\"].",
    ),
    tool(
      "dep_list",
      "List typed dependency edges for a task. args: [\"bk-task\"].",
    ),
    tool(
      "dep_remove",
      "Remove one typed edge idempotently. args: [\"bk-task\", \"bk-target\", \"--type\", \"blocks\"].",
    ),
    tool(
      "dep_tree",
      "Return a cycle-safe dependency tree for a task. args: [\"bk-task\"].",
    ),
    tool(
      "dep_traverse",
      "Traverse typed edges. args: [\"bk-task\", \"--direction\", \"incoming|outgoing|both\", \"--type\", \"blocks\", \"--depth\", \"2\"].",
    ),
    tool("dep_graph", "Export stable JSON nodes and typed edges."),
    tool("dep_check", "Check missing targets, cycles, and duplicate edges."),
    tool("doctor", "Run read-only task-store integrity diagnostics. args: []."),
    tool(
      "cluster_status",
      "Report local/cluster mode, transport admission, leader, quorum, ReadIndex, leases, projections, and recovery state. args: [].",
    ),
    tool(
      "platform_status",
      "Alias for cluster_status with transport and recovery diagnostics. args: [].",
    ),
    tool(
      "merge",
      "Consolidate a reviewed duplicate into a canonical task. args: [\"duplicate-id\", \"canonical-id\"].",
    ),
    tool("remember", "Persist a durable insight. args: [\"insight text\"]."),
    tool("memories", "List persisted memories."),
    tool("inspect", "Inspect a task by content hash. args: [\"<hex>\"]."),
    tool("compact", "Retire closed tasks into the archive."),
    tool("backup_list", "List all task backups in workspace. args: []."),
    tool(
      "backup_preview",
      "Preview divergence between backup and current store. args: [\"path\"].",
    ),
    tool(
      "backup_restore",
      "Restore a validated backup into Mnesia. args: [\"path\"].",
    ),
    tool("backup_prune", "Prune old backups. args: [\"--keep\", \"5\"]."),
    tool(
      "sync_conflicts",
      "List recorded replication and federation conflicts. args: [].",
    ),
    tool(
      "sync_conflict_resolve",
      "Resolve and clear a recorded conflict. args: [\"conflict-id\"].",
    ),
    tool(
      "sync_conflict_clear",
      "Clear all recorded replication conflicts. args: [].",
    ),
    tool(
      "sync_identity",
      "Print this replica's public key for provisioning a peer. args: [].",
    ),
    tool(
      "sync_trust",
      "Explicitly trust a peer key. args: [\"<public-key>\", \"--expires-at\", \"NS\"].",
    ),
    tool(
      "sync_revoke",
      "Revoke a previously trusted replica key. args: [\"<public-key>\"].",
    ),
    tool(
      "sync_rotate",
      "Rotate replica trust. args: [\"<old-key>\", \"<new-key>\", \"--overlap\", \"NS\", \"--expires-at\", \"NS\"].",
    ),
    tool(
      "journal_tail",
      "Tail committed changefeed journal events. args: [\"--after\", \"0\"].",
    ),
    tool("gate_satisfy", "Resolve a manual gate. args: [\"gate-id\"]."),
    tool(
      "gate_list",
      "List gates deterministically; optional --state all|open|pending.",
    ),
    tool(
      "gate_show",
      "Show gate evaluation, waiters, local escalation data, and audit.",
    ),
    tool(
      "gate_check",
      "Evaluate gate state and waiter readiness without mutation.",
    ),
    tool(
      "gate_resolve",
      "Resolve with optional --dry-run, --actor, and --reason.",
    ),
    tool(
      "gate_fact_ingest",
      "Verify and atomically persist signed external fact data.",
    ),
    tool(
      "wisp_create",
      "Create local-only wisp; optional --ttl seconds or --expires-at.",
    ),
    tool(
      "wisp_list",
      "List wisps deterministically; optional --state all|active|expired.",
    ),
    tool("wisp_promote", "Archive source and promote a wisp to a normal task."),
    tool("wisp_digest", "Derive a non-destructive wisp digest/squash view."),
    tool("wisp_burn", "Archive canonical current head before removing a wisp."),
    tool("wisp_gc", "Deterministically burn expired wisps; supports --dry-run."),
    tool("wisp_archive", "List ordered wisp archive evidence."),
    tool(
      "molecule_register",
      "Register immutable declarative template JSON. args: [\"<json>\"].",
    ),
    tool("molecule_list", "List registered molecule templates."),
    tool("molecule_show", "Show a template. args: [\"<hash>\"]."),
    tool(
      "molecule_instantiate",
      "Atomically instantiate. args: [\"<hash>\",\"--idempotency-key\",\"key\",\"name=value\"...].",
    ),
    tool(
      "molecule_compose",
      "Compose two templates. args: [\"name\",\"left-hash\",\"right-hash\"].",
    ),
    tool("molecule_instance", "Show instance provenance and tasks."),
    tool("molecule_provenance", "Show task-to-template provenance."),
    tool("molecule_progress", "Derive instance progress."),
    tool("molecule_current", "List current ready instance steps."),
    tool("molecule_distill", "Derive a non-destructive instance digest."),
    tool(
      "rule_register",
      "Register an unapproved local rule artifact. args: [\"name\", \"source\"].",
    ),
    tool("rule_list", "List local rule artifacts and approval state."),
    tool("rule_show", "Show a local rule artifact. args: [\"hash\"]."),
    tool("rule_approve", "Approve a local rule hash. args: [\"hash\"]."),
    tool("rule_revoke", "Revoke local rule approval. args: [\"hash\"]."),
    tool(
      "rule_eval",
      "Evaluate an approved rule against an immutable task view. args: [\"hash\", \"--caller\", \"name\", \"--task\", \"task-id\"].",
    ),
    tool(
      "rule_audit",
      "List durable local rule audit records. Optional args: [\"hash\"].",
    ),
  ]
}

fn tool(name: String, description: String) -> json.Json {
  json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
    #(
      "inputSchema",
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "args",
              json.object([
                #("type", json.string("array")),
                #("items", json.object([#("type", json.string("string"))])),
              ]),
            ),
          ]),
        ),
        #("required", json.array([], of: fn(j) { j })),
      ]),
    ),
  ])
}
