#!/bin/sh
# bankai installer — builds the escript and puts `bankai` on your PATH.
#
# Requires Erlang/OTP (the escript wraps `erl`). This is bankai's honest
# tradeoff vs beads's single static Go binary: no OTP, no bankai.
set -e

# gleam/rebar3 live in /opt/homebrew/bin, off the stripped shell PATH —
# same convention as the Makefile.
export PATH="/opt/homebrew/bin:$PATH"

# sanity: Erlang/OTP must be present for the escript to run.
if ! command -v erl >/dev/null 2>&1; then
  echo "bankai needs Erlang/OTP on PATH (the escript wraps 'erl')." >&2
  echo "Install it first, e.g.:  brew install erlang" >&2
  exit 1
fi
if ! command -v gleam >/dev/null 2>&1; then
  echo "bankai needs Gleam to build. Install it first, e.g.:  brew install gleam" >&2
  exit 1
fi

# build the ./bankai escript via the Makefile target
make escript

# install it somewhere on PATH — prefer $BINDIR or ~/.local/bin (no sudo),
# fall back to /usr/local/bin when writable.
DEST="${BINDIR:-$HOME/.local/bin}"
if [ ! -w "$(dirname "$DEST")" ] 2>/dev/null && [ -w /usr/local/bin ]; then
  DEST="/usr/local/bin"
fi
mkdir -p "$DEST"
cp dist/bankai "$DEST/bankai"
chmod +x "$DEST/bankai"

echo ""
echo "Installed bankai -> $DEST/bankai"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "NOTE: $DEST is not on your PATH. Add it:  export PATH=\"$DEST:\$PATH\"" ;;
esac
echo "Run:  bankai --help"
