//// ADR-0001 verification gate: determinism + content-addressing of Task state.

import gleeunit
import gleeunit/should
import gleam/option
import gleam/string
import gleamunison/identity
import bankai/ast_bridge
import bankai/builder
import bankai/types.{Blocks, InProgress, Open, Relationship}

pub fn main() {
  gleeunit.main()
}

pub fn identical_tasks_same_hash_test() {
  let t1 =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  let t2 =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  identity.hash_equal(t1.content_hash, t2.content_hash)
  |> should.be_true
}

pub fn single_field_mutation_changes_hash_test() {
  let t1 =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  let t2 =
    builder.build("bk-0001", "Write spec", "desc", InProgress, option.None, 1, 1000, 1000, [])
  identity.hash_equal(t1.content_hash, t2.content_hash)
  |> should.be_false
}

pub fn rehash_idempotent_test() {
  let t =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  identity.hash_equal(ast_bridge.rehash(t).content_hash, t.content_hash)
  |> should.be_true
}

pub fn content_hash_valid_test() {
  let t =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  ast_bridge.content_hash_valid(t)
  |> should.be_true
}

pub fn relationship_order_does_not_change_hash_test() {
  // Determinism: relationship list order must not affect the hash (sorted).
  let r1 = Relationship("bk-0099", Blocks)
  let r2 = Relationship("bk-0002", Blocks)
  let t1 = builder.build("bk-0001", "t", "d", Open, option.None, 1, 1, 1, [r1, r2])
  let t2 = builder.build("bk-0001", "t", "d", Open, option.None, 1, 1, 1, [r2, r1])
  identity.hash_equal(t1.content_hash, t2.content_hash)
  |> should.be_true
}

pub fn short_id_format_test() {
  let t =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  ast_bridge.task_short_id(t)
  |> string.starts_with("bk-")
  |> should.be_true
}
