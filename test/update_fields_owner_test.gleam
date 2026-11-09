//// Focused regressions for the shared update-field owner (bk-1a19):
//// one function decides what changed and applies it, so the CLI and the
//// daemon cannot drift on the same grammar.

import bankai/builder
import bankai/cli/parser
import bankai/task_update
import bankai/types.{Open}
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn seed_task() {
  builder.build("bk-0001", "Title", "seed", Open, option.None, 3, 1, 1, [])
}

pub fn same_value_update_is_a_no_op_test() {
  let assert Ok(args) =
    parser.parse_update_args(["bk-0001", "--description", "seed"])
  let assert Ok(fields) = task_update.fields_from_args(args)
  let #(changed, updated) = task_update.apply(seed_task(), fields)
  changed |> should.be_false
  updated.description |> should.equal("seed")
}

pub fn title_update_changes_the_task_test() {
  let assert Ok(args) =
    parser.parse_update_args(["bk-0001", "--title", "New title"])
  let assert Ok(fields) = task_update.fields_from_args(args)
  let #(changed, updated) = task_update.apply(seed_task(), fields)
  changed |> should.be_true
  updated.title |> should.equal("New title")
}

pub fn invalid_status_is_rejected_at_the_boundary_test() {
  let assert Ok(args) = parser.parse_update_args(["bk-0001", "bogus"])
  task_update.fields_from_args(args)
  |> should.equal(Error("invalid status: bogus"))
}

pub fn heartbeat_alone_has_no_simple_fields_test() {
  let assert Ok(alone) = parser.parse_update_args(["bk-0001", "--heartbeat"])
  parser.simple_fields_requested(alone) |> should.be_false

  let assert Ok(with_description) =
    parser.parse_update_args(["bk-0001", "--heartbeat", "--description", "x"])
  parser.simple_fields_requested(with_description) |> should.be_true
}
