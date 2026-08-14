import bankai/builder
import bankai/graph
import bankai/mnesia_store
import bankai/molecules/store
import bankai/molecules/types as molecule_types
import bankai/serde
import bankai/time
import bankai/types.{type Task, Completed, Open, ParentChild, Relationship}
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity

pub fn register(
  workspace: String,
  source: String,
) -> Result(json.Json, String) {
  use _ <- result.try(mnesia_store.init(workspace))
  use _ <- result.try(store.init(workspace))
  use template <- result.try(molecule_types.decode_template(source))
  let canonical = molecule_types.canonical_source(template)
  let hash = digest(canonical)
  store.register(workspace, hash, template, canonical)
  |> result.map(fn(_) {
    json.object([
      #("hash", json.string(hash)),
      #("template", molecule_types.to_json(template)),
    ])
  })
}

pub fn list(workspace: String) -> Result(json.Json, String) {
  use _ <- result.try(store.init(workspace))
  store.list(workspace)
  |> result.map(fn(values) { json.array(values, of: store.summary_json) })
}

pub fn show(workspace: String, hash: String) -> Result(json.Json, String) {
  use _ <- result.try(store.init(workspace))
  store.get(workspace, hash)
  |> result.map(fn(found) {
    json.object([
      #("hash", json.string(hash)),
      #("template", molecule_types.to_json(found.0)),
    ])
  })
}

pub fn instantiate(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
  raw_bindings: List(String),
) -> Result(json.Json, String) {
  case idempotency_key == "" {
    True -> Error("molecule instantiation requires an idempotency key")
    False -> {
      use _ <- result.try(mnesia_store.init(workspace))
      use _ <- result.try(store.init(workspace))
      use template <- result.try(store.get(workspace, template_hash))
      use bound <- result.try(molecule_types.bind(template.0, raw_bindings))
      let #(bindings, bound_nodes) = bound
      let bindings_json = bindings_to_json(bindings) |> json.to_string
      let fingerprint = digest(template_hash <> "\n" <> bindings_json)
      let instance_id =
        "mol-"
        <> string.slice(digest(template_hash <> "\n" <> idempotency_key), 0, 12)
      use tasks <- result.try(materialize(template.0, bound_nodes, instance_id))
      let rows =
        tasks
        |> list.map(fn(pair) {
          let #(node, task) = pair
          #(
            task.id,
            identity.hash_to_debug_string(task.content_hash),
            serde.task_to_json_string(task),
            node,
          )
        })
      store.instantiate(
        workspace,
        template_hash,
        idempotency_key,
        fingerprint,
        instance_id,
        bindings_json,
        rows,
        time.now(),
      )
      |> result.map(instance_json)
    }
  }
}

pub fn compose(
  workspace: String,
  name: String,
  left_hash: String,
  right_hash: String,
) -> Result(json.Json, String) {
  use left <- result.try(store.get(workspace, left_hash))
  use right <- result.try(store.get(workspace, right_hash))
  let molecule_types.Template(_, _, left_variables, left_nodes, left_edges) =
    left.0
  let molecule_types.Template(_, _, right_variables, right_nodes, right_edges) =
    right.0
  let right_nodes =
    list.map(right_nodes, fn(node) { prefix_node("right.", node) })
  let composed =
    molecule_types.Template(
      1,
      name,
      unique_variables(list.append(left_variables, right_variables)),
      list.append(left_nodes, right_nodes),
      list.append(left_edges, list.map(right_edges, prefix_edge)),
    )
  let source = molecule_types.canonical_source(composed)
  register(workspace, source)
}

pub fn instance(
  workspace: String,
  instance_id: String,
) -> Result(json.Json, String) {
  use saved <- result.try(store.instance(workspace, instance_id))
  use tasks <- result.try(tasks_for_instance(workspace, saved.node_tasks))
  Ok(instance_detail_json(instance_id, saved, tasks))
}

pub fn provenance(
  workspace: String,
  task_id: String,
) -> Result(json.Json, String) {
  store.provenance(workspace, task_id)
  |> result.map(fn(found) {
    json.object([
      #("task_id", json.string(task_id)),
      #("template_hash", json.string(found.0)),
      #("instance_id", json.string(found.1)),
      #("node", json.string(found.2)),
    ])
  })
}

pub fn provenance_by_node(
  workspace: String,
  instance_id: String,
  node: String,
) -> Result(String, String) {
  use saved <- result.try(store.instance(workspace, instance_id))
  saved.node_tasks
  |> list.find(fn(pair) { pair.0 == node })
  |> result.map(fn(pair) { pair.1 })
  |> result.map_error(fn(_) { "no such molecule node: " <> node })
}

pub fn progress(
  workspace: String,
  instance_id: String,
) -> Result(json.Json, String) {
  use saved <- result.try(store.instance(workspace, instance_id))
  use tasks <- result.try(tasks_for_instance(workspace, saved.node_tasks))
  let completed =
    tasks |> list.filter(fn(pair) { pair.1.status == Completed }) |> list.length
  let total = list.length(tasks)
  let percentage = case total {
    0 -> 0.0
    _ -> int_to_float(completed) /. int_to_float(total) *. 100.0
  }
  Ok(
    json.object([
      #("instance_id", json.string(instance_id)),
      #("completed", json.int(completed)),
      #("total", json.int(total)),
      #("completion_pct", json.float(percentage)),
    ]),
  )
}

pub fn current(
  workspace: String,
  instance_id: String,
) -> Result(json.Json, String) {
  use saved <- result.try(store.instance(workspace, instance_id))
  use tasks <- result.try(tasks_for_instance(workspace, saved.node_tasks))
  let current =
    graph.ready_tasks_at(list.map(tasks, fn(pair) { pair.1 }), time.now())
  Ok(
    json.object([
      #("instance_id", json.string(instance_id)),
      #("tasks", json.array(current, of: serde.task_to_json)),
    ]),
  )
}

pub fn distill(
  workspace: String,
  instance_id: String,
) -> Result(json.Json, String) {
  use saved <- result.try(store.instance(workspace, instance_id))
  use tasks <- result.try(tasks_for_instance(workspace, saved.node_tasks))
  use progress <- result.try(progress(workspace, instance_id))
  Ok(
    json.object([
      #("instance_id", json.string(instance_id)),
      #("template_hash", json.string(saved.template_hash)),
      #("summary", progress),
      #(
        "tasks",
        json.array(tasks, of: fn(pair) {
          json.object([
            #("node", json.string(pair.0)),
            #("task", serde.task_to_json(pair.1)),
          ])
        }),
      ),
      #("source_history_preserved", json.bool(True)),
    ]),
  )
}

fn materialize(
  template: molecule_types.Template,
  nodes: List(molecule_types.BoundNode),
  instance_id: String,
) -> Result(List(#(String, Task)), String) {
  let now = time.now()
  let ids =
    nodes
    |> list.map(fn(node) {
      let molecule_types.BoundNode(name, _, _, _, _, _, _) = node
      #(name, "bk-" <> string.slice(digest(instance_id <> "\n" <> name), 0, 12))
    })
  nodes
  |> list.try_map(fn(node) {
    let molecule_types.BoundNode(
      name,
      title,
      description,
      kind,
      priority,
      labels,
      parent,
    ) = node
    use id <- result.try(lookup(ids, name, "node"))
    let parent_id = case parent {
      option.Some(parent_name) ->
        case lookup(ids, parent_name, "parent") {
          Ok(value) -> option.Some(value)
          Error(_) -> option.None
        }
      option.None -> option.None
    }
    let edges =
      template.edges
      |> list.filter(fn(edge) {
        let molecule_types.Edge(from, _, _) = edge
        from == name
      })
      |> list.filter_map(fn(edge) {
        let molecule_types.Edge(_, to, relation) = edge
        lookup(ids, to, "edge")
        |> result.map(fn(target) { Relationship(target, relation) })
      })
    let parent_edges = case parent_id {
      option.Some(parent) -> [Relationship(parent, ParentChild)]
      option.None -> []
    }
    let task =
      builder.build_full(
        id,
        title,
        description,
        Open,
        option.None,
        priority,
        now,
        now,
        list.append(edges, parent_edges),
        labels,
        parent_id,
        kind,
      )
    Ok(#(name, task))
  })
}

fn tasks_for_instance(
  workspace: String,
  nodes: List(#(String, String)),
) -> Result(List(#(String, Task)), String) {
  nodes
  |> list.try_map(fn(pair) {
    mnesia_store.get_current(workspace, pair.1)
    |> result.map(fn(task) { #(pair.0, task) })
  })
}

fn instance_json(value: store.Instance) -> json.Json {
  json.object([
    #("instance_id", json.string(value.instance_id)),
    #("template_hash", json.string(value.template_hash)),
    #("idempotency_key", json.string(value.idempotency_key)),
    #("bindings", raw_json(value.bindings_json)),
    #("nodes", node_tasks_json(value.node_tasks)),
    #("created_at", json.int(value.created_at)),
    #("replayed", json.bool(value.replayed)),
  ])
}

fn instance_detail_json(
  instance_id: String,
  saved: store.InstanceData,
  tasks: List(#(String, Task)),
) -> json.Json {
  json.object([
    #("instance_id", json.string(instance_id)),
    #("template_hash", json.string(saved.template_hash)),
    #("idempotency_key", json.string(saved.idempotency_key)),
    #("bindings", raw_json(saved.bindings_json)),
    #(
      "nodes",
      json.array(tasks, of: fn(pair) {
        json.object([
          #("node", json.string(pair.0)),
          #("task_id", json.string(pair.1.id)),
          #("task", serde.task_to_json(pair.1)),
        ])
      }),
    ),
  ])
}

fn node_tasks_json(values: List(#(String, String))) -> json.Json {
  json.array(values, of: fn(value) {
    json.object([
      #("node", json.string(value.0)),
      #("task_id", json.string(value.1)),
    ])
  })
}

fn bindings_to_json(bindings: List(#(String, String))) -> json.Json {
  json.object(
    list.map(bindings, fn(binding) { #(binding.0, json.string(binding.1)) }),
  )
}

fn raw_json(source: String) -> json.Json {
  json.object([#("canonical", json.string(source))])
}

fn digest(value: String) -> String {
  value
  |> bit_array.from_string
  |> identity.hash_bytes
  |> identity.hash_to_debug_string
}

fn lookup(
  values: List(#(String, String)),
  name: String,
  kind: String,
) -> Result(String, String) {
  values
  |> list.find(fn(pair) { pair.0 == name })
  |> result.map(fn(pair) { pair.1 })
  |> result.map_error(fn(_) { "unknown molecule " <> kind <> ": " <> name })
}

fn unique_variables(
  values: List(molecule_types.Variable),
) -> List(molecule_types.Variable) {
  list.fold(values, [], fn(acc, variable) {
    let molecule_types.Variable(name, _, _) = variable
    case
      list.any(acc, fn(existing) {
        let molecule_types.Variable(existing_name, _, _) = existing
        existing_name == name
      })
    {
      True -> acc
      False -> list.append(acc, [variable])
    }
  })
}

fn prefix_node(
  prefix: String,
  node: molecule_types.Node,
) -> molecule_types.Node {
  let molecule_types.Node(
    name,
    title,
    description,
    kind,
    priority,
    labels,
    parent,
  ) = node
  molecule_types.Node(
    prefix <> name,
    title,
    description,
    kind,
    priority,
    labels,
    option.map(parent, fn(value) { prefix <> value }),
  )
}

fn prefix_edge(edge: molecule_types.Edge) -> molecule_types.Edge {
  let molecule_types.Edge(from, to, relation) = edge
  molecule_types.Edge("right." <> from, "right." <> to, relation)
}

@external(erlang, "erlang", "float")
fn int_to_float(value: Int) -> Float
