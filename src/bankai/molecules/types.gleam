import bankai/graph
import bankai/serde
import bankai/types.{
  type RelationType, type TaskKind, Blocks, CausedBy, ConditionalBlocks,
  DiscoveredFrom, ParentChild, Tracks, Validates, WaitsFor,
}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set
import gleam/string

pub type Variable {
  Variable(name: String, required: Bool, default: Option(String))
}

pub type Node {
  Node(
    name: String,
    title: String,
    description: String,
    kind: TaskKind,
    priority: Int,
    labels: List(String),
    parent: Option(String),
  )
}

pub type Edge {
  Edge(from: String, to: String, relation: RelationType)
}

pub type Template {
  Template(
    schema: Int,
    name: String,
    variables: List(Variable),
    nodes: List(Node),
    edges: List(Edge),
  )
}

pub type BoundNode {
  BoundNode(
    name: String,
    title: String,
    description: String,
    kind: TaskKind,
    priority: Int,
    labels: List(String),
    parent: Option(String),
  )
}

pub fn decode_template(source: String) -> Result(Template, String) {
  json.parse(from: source, using: template_decoder())
  |> result.map_error(fn(_) { "molecule template decode failed" })
  |> result.try(validate)
}

pub fn validate(template: Template) -> Result(Template, String) {
  let variable_names =
    list.map(template.variables, fn(variable) { variable.name })
  let node_names = list.map(template.nodes, fn(node) { node.name })
  case template.schema != 1 {
    True -> Error("unsupported molecule schema")
    False ->
      case template.name == "" || list.is_empty(template.nodes) {
        True -> Error("molecule name and nodes are required")
        False ->
          case unique(variable_names), unique(node_names) {
            False, _ -> Error("duplicate molecule variable")
            _, False -> Error("duplicate molecule node")
            True, True ->
              validate_references(template, variable_names, node_names)
          }
      }
  }
}

pub fn bind(
  template: Template,
  raw_bindings: List(String),
) -> Result(#(List(#(String, String)), List(BoundNode)), String) {
  use supplied <- result.try(parse_bindings(raw_bindings))
  use resolved <- result.try(resolve_bindings(template.variables, supplied))
  let allowed = list.map(template.variables, fn(variable) { variable.name })
  let unknown =
    supplied
    |> dict.keys
    |> list.filter(fn(name) { !list.contains(allowed, name) })
  case unknown {
    [name, ..] -> Error("unknown molecule binding: " <> name)
    [] ->
      template.nodes
      |> list.try_map(fn(node) {
        use title <- result.try(interpolate(node.title, resolved))
        use description <- result.try(interpolate(node.description, resolved))
        Ok(BoundNode(
          node.name,
          title,
          description,
          node.kind,
          node.priority,
          node.labels,
          node.parent,
        ))
      })
      |> result.map(fn(nodes) { #(resolved, nodes) })
  }
}

pub fn to_json(template: Template) -> json.Json {
  let Template(schema, name, variables, nodes, edges) = template
  json.object([
    #("schema", json.int(schema)),
    #("name", json.string(name)),
    #("variables", json.array(variables, of: variable_json)),
    #("nodes", json.array(nodes, of: node_json)),
    #("edges", json.array(edges, of: edge_json)),
  ])
}

pub fn canonical_source(template: Template) -> String {
  json.to_string(to_json(template))
}

fn validate_references(
  template: Template,
  variable_names: List(String),
  node_names: List(String),
) -> Result(Template, String) {
  let texts =
    template.nodes
    |> list.flat_map(fn(node) { [node.title, node.description] })
  let used_variables = texts |> list.flat_map(placeholders) |> list.unique
  let unknown_variables =
    used_variables
    |> list.filter(fn(name) { !list.contains(variable_names, name) })
  let bad_parent =
    template.nodes
    |> list.find(fn(node) {
      case node.parent {
        option.Some(parent) ->
          parent == node.name || !list.contains(node_names, parent)
        option.None -> False
      }
    })
  let bad_edge =
    template.edges
    |> list.find(fn(edge) {
      !list.contains(node_names, edge.from)
      || !list.contains(node_names, edge.to)
    })
  case unknown_variables, bad_parent, bad_edge {
    [name, ..], _, _ -> Error("unknown molecule variable: " <> name)
    [], Ok(_), _ -> Error("invalid molecule parent reference")
    [], Error(_), Ok(_) -> Error("unknown molecule edge endpoint")
    [], Error(_), Error(_) -> validate_blocking_cycles(template)
  }
}

fn validate_blocking_cycles(template: Template) -> Result(Template, String) {
  let blocking =
    template.edges
    |> list.filter(fn(edge) { graph.is_blocking_relation(edge.relation) })
    |> list.map(fn(edge) { #(edge.from, edge.to) })
  case
    blocking
    |> list.any(fn(edge) { graph.would_cycle(blocking, edge) })
  {
    True -> Error("molecule blocking cycle")
    False -> validate_parent_cycles(template)
  }
}

fn validate_parent_cycles(template: Template) -> Result(Template, String) {
  let parents =
    template.nodes
    |> list.filter_map(fn(node) {
      case node.parent {
        option.Some(parent) -> Ok(#(node.name, parent))
        option.None -> Error(Nil)
      }
    })
  case
    parents
    |> list.any(fn(edge) { reaches(parents, edge.1, edge.0, set.new()) })
  {
    True -> Error("molecule parent cycle")
    False -> Ok(template)
  }
}

fn reaches(
  edges: List(#(String, String)),
  current: String,
  target: String,
  seen: set.Set(String),
) -> Bool {
  case current == target || set.contains(seen, current) {
    True -> current == target
    False ->
      edges
      |> list.filter(fn(edge) { edge.0 == current })
      |> list.any(fn(edge) {
        reaches(edges, edge.1, target, set.insert(seen, current))
      })
  }
}

fn parse_bindings(
  values: List(String),
) -> Result(Dict(String, String), String) {
  values
  |> list.fold(Ok(dict.new()), fn(acc, encoded) {
    use parsed <- result.try(acc)
    case string.split_once(encoded, "=") {
      Ok(#(name, value)) ->
        case name == "" || dict.has_key(parsed, name) {
          True -> Error("invalid or duplicate molecule binding: " <> encoded)
          False -> Ok(dict.insert(parsed, name, value))
        }
      Error(Nil) -> Error("invalid molecule binding: " <> encoded)
    }
  })
}

fn resolve_bindings(
  variables: List(Variable),
  supplied: Dict(String, String),
) -> Result(List(#(String, String)), String) {
  variables
  |> list.try_map(fn(variable) {
    case
      dict.get(supplied, variable.name),
      variable.default,
      variable.required
    {
      Ok(value), _, _ -> Ok(#(variable.name, value))
      Error(Nil), option.Some(value), _ -> Ok(#(variable.name, value))
      Error(Nil), option.None, True ->
        Error("missing molecule binding: " <> variable.name)
      Error(Nil), option.None, False -> Ok(#(variable.name, ""))
    }
  })
}

fn interpolate(
  text: String,
  bindings: List(#(String, String)),
) -> Result(String, String) {
  let rendered =
    list.fold(bindings, text, fn(current, binding) {
      string.replace(current, "{{" <> binding.0 <> "}}", binding.1)
    })
  case placeholders(rendered) {
    [] -> Ok(rendered)
    [name, ..] -> Error("unbound molecule variable: " <> name)
  }
}

fn placeholders(text: String) -> List(String) {
  text
  |> string.split("{{")
  |> list.drop(1)
  |> list.filter_map(fn(part) {
    case string.split_once(part, "}}") {
      Ok(#(name, _)) -> Ok(name)
      Error(Nil) -> Error(Nil)
    }
  })
}

fn unique(values: List(String)) -> Bool {
  list.length(values) == list.length(list.unique(values))
}

fn template_decoder() -> decode.Decoder(Template) {
  use schema <- decode.field("schema", decode.int)
  use name <- decode.field("name", decode.string)
  use variables <- decode.optional_field(
    "variables",
    [],
    decode.list(of: variable_decoder()),
  )
  use nodes <- decode.field("nodes", decode.list(of: node_decoder()))
  use edges <- decode.optional_field(
    "edges",
    [],
    decode.list(of: edge_decoder()),
  )
  decode.success(Template(schema, name, variables, nodes, edges))
}

fn variable_decoder() -> decode.Decoder(Variable) {
  use name <- decode.field("name", decode.string)
  use required <- decode.optional_field("required", False, decode.bool)
  use default <- decode.optional_field(
    "default",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(Variable(name, required, default))
}

fn node_decoder() -> decode.Decoder(Node) {
  use name <- decode.field("name", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use kind <- decode.optional_field("kind", "task", decode.string)
  use priority <- decode.optional_field("priority", 1, decode.int)
  use labels <- decode.optional_field(
    "labels",
    [],
    decode.list(of: decode.string),
  )
  use parent <- decode.optional_field(
    "parent",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(Node(
    name,
    title,
    description,
    serde.kind_from_string(kind),
    priority,
    labels,
    parent,
  ))
}

fn edge_decoder() -> decode.Decoder(Edge) {
  use from <- decode.field("from", decode.string)
  use to <- decode.field("to", decode.string)
  use relation <- decode.field("relation", decode.string)
  case serde.relation_from_string(relation) {
    Ok(kind) -> decode.success(Edge(from, to, kind))
    Error(Nil) -> decode.failure(Edge(from, to, Blocks), "valid relation")
  }
}

fn variable_json(variable: Variable) -> json.Json {
  json.object([
    #("name", json.string(variable.name)),
    #("required", json.bool(variable.required)),
    #("default", json.nullable(variable.default, of: json.string)),
  ])
}

fn node_json(node: Node) -> json.Json {
  json.object([
    #("name", json.string(node.name)),
    #("title", json.string(node.title)),
    #("description", json.string(node.description)),
    #("kind", json.string(serde.kind_to_string(node.kind))),
    #("priority", json.int(node.priority)),
    #("labels", json.array(node.labels, of: json.string)),
    #("parent", json.nullable(node.parent, of: json.string)),
  ])
}

fn edge_json(edge: Edge) -> json.Json {
  json.object([
    #("from", json.string(edge.from)),
    #("to", json.string(edge.to)),
    #("relation", json.string(relation_name(edge.relation))),
  ])
}

fn relation_name(relation: RelationType) -> String {
  case relation {
    Blocks -> "blocks"
    WaitsFor -> "waits_for"
    ConditionalBlocks -> "conditional_blocks"
    ParentChild -> "parent_child"
    DiscoveredFrom -> "discovered_from"
    Tracks -> "tracks"
    CausedBy -> "caused_by"
    Validates -> "validates"
    _ -> "relates_to"
  }
}
