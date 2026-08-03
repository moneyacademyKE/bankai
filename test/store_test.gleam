import gleeunit
import gleeunit/should
import gleam/list
import gleam/option
import gleamunison/identity
import bankai/builder
import bankai/storage/store
import bankai/types.{Open}

pub fn main() {
  gleeunit.main()
}

pub fn put_get_roundtrip_test() {
  let t =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  let store = store.new() |> store.put(t)
  let retrieved = store.get(store, t.content_hash)

  let retrieved_task = should.be_ok(retrieved)
  identity.hash_equal(retrieved_task.content_hash, t.content_hash)
  |> should.be_true
  retrieved_task.id
  |> should.equal("bk-0001")
}

pub fn find_by_id_test() {
  let t =
    builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
  let store = store.new() |> store.put(t)
  let found = store.find_by_id(store, "bk-0001")

  should.be_ok(found)
  |> fn(t) { t.title }
  |> should.equal("Write spec")
}

pub fn list_stable_order_and_size_test() {
  let t1 =
    builder.build("bk-0001", "one", "d", Open, option.None, 1, 1000, 1000, [])
  let t2 =
    builder.build("bk-0002", "two", "d", Open, option.None, 1, 1000, 1000, [])
  let store = store.new() |> store.put(t1) |> store.put(t2)

  store.list(store)
  |> list.length()
  |> should.equal(2)

  store.size(store)
  |> should.equal(2)
}

pub fn from_list_roundtrip_test() {
  let t1 =
    builder.build("bk-0001", "one", "d", Open, option.None, 1, 1000, 1000, [])
  let rebuilt = store.from_list([t1])
  store.size(rebuilt)
  |> should.equal(1)
}
