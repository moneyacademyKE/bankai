import aarondb/fact
import aarondb/shared/ast
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/option.{type Option}

pub type ShardMap {
  ShardMap(
    nodes: Dict(Int, process.Pid),
    vnodes: Dict(Int, Int),
    // Hash -> ShardId
    sorted_hashes: List(Int),
  )
}

pub type ShardedDb(shard_type) {
  ShardedDb(
    shards: Dict(Int, shard_type),
    shard_count: Int,
    cluster_id: String,
    shard_map: ShardMap,
  )
}

pub type PullResult {
  PullMap(Dict(String, PullResult))
  PullSingle(fact.Value)
  PullMany(List(fact.Value))
  PullNestedMany(List(PullResult))
  PullRawBinary(BitArray)
}

pub type TraversalStep {
  Out(attribute: String)
  In(attribute: String)
}

pub type TraversalExpr =
  List(TraversalStep)

pub type QueryResult {
  QueryResult(
    rows: List(Dict(String, fact.Value)),
    metadata: QueryMetadata,
    updated_columnar_store: Option(Dict(String, List(internal.StorageChunk))),
  )
}

pub type QueryMetadata {
  QueryMetadata(
    tx_id: Option(Int),
    valid_time: Option(Int),
    execution_time_ms: Int,
    index_hits: Int,
    plan: String,
    shard_id: Option(Int),
    aggregates: Dict(String, ast.AggFunc),
  )
}

pub type ReactiveDelta {
  Initial(QueryResult)
  Delta(added: QueryResult, removed: QueryResult)
}
