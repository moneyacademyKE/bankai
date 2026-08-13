import bankai/daemon_store
import bankai/service_auth
import bankai/socket
import gleam/erlang/process
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_service_auth_test"

fn reset() {
  service_auth.reset_for_test(workspace)
  let _ = daemon_store.boot(workspace)
  Nil
}

pub fn read_and_write_capabilities_are_distinct_test() {
  reset()
  let read = should.be_ok(service_auth.mint(workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(workspace, "write", 3600))

  service_auth.authorize_request(workspace, read, "list", []) |> should.be_ok
  service_auth.authorize_request(workspace, read, "create", [])
  |> should.be_error
  service_auth.authorize_request(workspace, write, "create", []) |> should.be_ok
  service_auth.authorize_request(workspace, write, "list", [])
  |> should.be_error
}

pub fn admin_capability_subsumes_read_and_write_test() {
  reset()
  let admin = should.be_ok(service_auth.mint(workspace, "admin", 3600))
  service_auth.authorize_request(workspace, admin, "list", []) |> should.be_ok
  service_auth.authorize_request(workspace, admin, "create", []) |> should.be_ok
  service_auth.authorize_request(workspace, admin, "auth_mint", [])
  |> should.be_ok
}

pub fn tampered_capability_is_rejected_test() {
  reset()
  let token = should.be_ok(service_auth.mint(workspace, "read", 3600))
  service_auth.authorize_request(workspace, token <> "x", "list", [])
  |> should.be_error
  |> string.contains("signature")
  |> should.be_true
}

pub fn authenticated_wire_fails_closed_and_enforces_scope_test() {
  reset()
  let read = should.be_ok(service_auth.mint(workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(workspace, "write", 3600))

  socket.handle_authenticated_line(
    workspace,
    "{\"method\":\"list\",\"params\":[],\"id\":1}",
  )
  |> string.contains("missing capability token")
  |> should.be_true

  let denied =
    "{\"method\":\"create\",\"params\":[\"denied\"],\"token\":\""
    <> read
    <> "\",\"id\":2}"
  socket.handle_authenticated_line(workspace, denied)
  |> string.contains("capability denied")
  |> should.be_true

  let allowed =
    "{\"method\":\"create\",\"params\":[\"allowed\"],\"token\":\""
    <> write
    <> "\",\"id\":3}"
  socket.handle_authenticated_line(workspace, allowed)
  |> string.contains("allowed")
  |> should.be_true
}

pub fn resident_service_accepts_attenuated_client_tokens_test() {
  let service_workspace = "/tmp/bankai_authenticated_service_test"
  service_auth.reset_for_test(service_workspace)
  let read = should.be_ok(service_auth.mint(service_workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(service_workspace, "write", 3600))
  let _ = process.spawn_unlinked(fn() { socket.serve(service_workspace) })
  process.sleep(200)

  socket.client_request_with_token(service_workspace, "list", [], read)
  |> should.be_ok
  socket.client_request_with_token(
    service_workspace,
    "auth_mint",
    ["read"],
    write,
  )
  |> should.be_error
  socket.client_request_with_token(
    service_workspace,
    "auth_mint",
    ["read", "--ttl", "60"],
    should.be_ok(service_auth.local_admin_token(service_workspace)),
  )
  |> should.be_ok
  socket.client_request_with_token(
    service_workspace,
    "create",
    ["denied over service"],
    read,
  )
  |> should.be_error
  socket.client_request_with_token(
    service_workspace,
    "create",
    ["allowed over service"],
    write,
  )
  |> should.be_ok
  |> string.contains("allowed over service")
  |> should.be_true
}
