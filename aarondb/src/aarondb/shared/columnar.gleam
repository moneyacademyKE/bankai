import aarondb/fact
import gleam/dict.{type Dict}

pub type ColumnChunk {
  ColumnChunk(
    attribute: String,
    values: List(fact.Value),
    max_tx: Int,
    is_compressed: Bool,
  )
}

pub type ColumnarStore =
  Dict(String, List(ColumnChunk))
