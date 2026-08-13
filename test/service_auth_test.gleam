import bankai/daemon_store
import bankai/service_auth
import bankai/socket
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

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

pub fn policy_is_explicit_and_parameter_sensitive_test() {
  reset()
  let read = should.be_ok(service_auth.mint(workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(workspace, "write", 3600))

  service_auth.authorize_request(workspace, read, "ready", []) |> should.be_ok
  service_auth.authorize_request(workspace, read, "ready", ["--claim", "agent"])
  |> should.be_error
  service_auth.authorize_request(workspace, write, "ready", ["--claim", "agent"])
  |> should.be_ok
  service_auth.authorize_request(workspace, read, "future_mutation", [])
  |> should.be_error
  |> string.contains("unknown service method")
  |> should.be_true
}

pub fn existing_permissive_secret_fails_closed_test() {
  let private_workspace = "/tmp/bankai_service_auth_permissions_test"
  let key = private_workspace <> "/service-auth.key"
  service_auth.reset_for_test(private_workspace)
  let _ = simplifile.create_directory_all(private_workspace)
  let _ = simplifile.write(string.repeat("x", times: 32), to: key)
  let _ = simplifile.set_permissions_octal(for_file_at: key, to: 0o644)

  service_auth.mint(private_workspace, "read", 60)
  |> should.be_error
  |> string.contains("permissions must be 0600")
  |> should.be_true
}

pub fn new_secret_is_private_test() {
  let private_workspace = "/tmp/bankai_service_auth_new_secret_test"
  let key = private_workspace <> "/service-auth.key"
  service_auth.reset_for_test(private_workspace)
  service_auth.mint(private_workspace, "read", 60) |> should.be_ok

  let info = should.be_ok(simplifile.file_info(key))
  simplifile.file_info_permissions_octal(info) |> should.equal(0o600)
}

pub fn concurrent_first_use_shares_one_private_secret_test() {
  let private_workspace = "/tmp/bankai_service_auth_race_test"
  let key = private_workspace <> "/service-auth.key"
  service_auth.reset_for_test(private_workspace)
  let replies = process.new_subject()
  let requests = [1, 2, 3, 4, 5, 6, 7, 8]
  let _ =
    requests
    |> list.map(fn(_) {
      process.spawn_unlinked(fn() {
        process.send(replies, service_auth.mint(private_workspace, "read", 60))
      })
    })

  requests
  |> list.each(fn(_) {
    process.receive_forever(from: replies)
    |> should.be_ok
  })
  let info = should.be_ok(simplifile.file_info(key))
  simplifile.file_info_permissions_octal(info) |> should.equal(0o600)
  info.size |> should.equal(32)
}

pub fn malformed_mint_arguments_are_rejected_test() {
  reset()
  case
    socket.handle_request(
      workspace,
      socket.Request("auth_mint", ["read", "--ttl"]),
    )
  {
    socket.ErrorResponse(message) ->
      message
      |> string.contains("requires <read|write|admin> [--ttl seconds]")
      |> should.be_true
    socket.OkResponse(_) -> False |> should.be_true
  }

  case
    socket.handle_request(
      workspace,
      socket.Request("auth_mint", ["read", "--unexpected"]),
    )
  {
    socket.ErrorResponse(_) -> True |> should.be_true
    socket.OkResponse(_) -> False |> should.be_true
  }
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
