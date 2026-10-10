//// Claim leases (bk-ccbf): a claim stamps an expiry so a dead agent's claim
//// can be reclaimed instead of jamming work forever.

import gleam/int
import gleam/option.{type Option}

pub const default_ttl_seconds = 1800

const micros_per_second = 1_000_000

/// Lease expiry for a claim made at `now` (µs) with `ttl_seconds`.
pub fn fresh(now: Int, ttl_seconds: Int) -> Option(Int) {
  option.Some(now + ttl_seconds * micros_per_second)
}

/// Parse a --ttl flag value, defaulting when absent/garbage.
pub fn ttl_from(value: Option(String)) -> Int {
  case value {
    option.Some(text) ->
      case int.parse(text) {
        Ok(seconds) -> seconds
        Error(_) -> default_ttl_seconds
      }
    option.None -> default_ttl_seconds
  }
}

/// True when the lease exists and its expiry is at or before `now`.
pub fn is_expired(lease: Option(Int), now: Int) -> Bool {
  case lease {
    option.Some(expires_at) -> expires_at <= now
    option.None -> False
  }
}
