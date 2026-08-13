# ADR-0009: Capability-authenticated resident service

- **Status:** Accepted
- **Date:** 2026-08-13

## Context

Bankai already has a resident UNIX-socket daemon that owns transactional Mnesia task authority and isolates concurrent connections. Its wire protocol previously carried only `method`, `params`, and `id`, so possession of local socket access implied full authority. AaronDB 4.2 supplies useful `Action`, `Resource`, `Capability`, `Token`, and subsumption policy, but explicitly does not authenticate token provenance.

The service needs separate read, write, and administrative authority without leaking credentials into task handlers or pretending that a local socket is a network identity system.

## Decision

Authenticate once at the JSON-line protocol edge and pass only method/parameter data to domain dispatch:

1. Bankai mints HMAC-SHA256 signed, expiring bearer tokens from a workspace-local 32-byte secret.
2. The secret is generated atomically at `.bankai/service-auth.key`, mode `0600`, and is never returned by a public API.
3. Verified claims are decoded into AaronDB `Token` data and checked through `auth.authorize/2`.
4. `read` authorizes query methods, `write` authorizes mutations, and `admin` subsumes both plus token minting.
5. Method and parameters are classified before dispatch; parameter-dependent mutations such as `ready --claim` require write authority.
6. Existing local CLI calls mint a short-lived admin token internally. External local agents use an attenuated token with `client_request_with_token`.
7. Missing, malformed, tampered, expired, or under-scoped tokens fail closed before any domain handler runs.

## Consequences

- Authorization is one composable policy boundary rather than checks scattered through handlers.
- AaronDB supplies authority vocabulary and subsumption, while Bankai owns authentication and secret lifecycle.
- Bearer tokens must not be logged or committed; compromise lasts until expiry or workspace-secret rotation.
- The service remains UNIX-domain local transport. Network exposure still requires TLS, peer identity, bootstrap policy, and revocation infrastructure; this ADR does not claim those.
- Mnesia remains task authority. Authentication does not create a second data store or alter transaction semantics.

## Rejected alternatives

- **Trust the socket alone:** cannot scope agents to read versus write.
- **Use AaronDB JSON tokens without signatures:** models authority but permits claim forgery; AaronDB documents this limitation.
- **Authorize inside each handler:** complects credentials with domain behavior and invites inconsistent omissions.
- **Expose a network listener now:** transport identity and operational hardening have not earned that expansion.

## Verification

`test/service_auth_test.gleam` covers read/write/admin separation, tamper rejection, fail-closed wire requests, admin-only minting, and a live concurrent resident-service round trip.
