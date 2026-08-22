#!/bin/sh
# bankai installer — builds the escript and puts `bankai` on your PATH.
#
# Installs TWO binaries from one build:
#   bankai       — the client CLI
#   bankai-serve — serve-dedicated path for the daemon (macOS; see agent note)
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
cp dist/bankai "$DEST/bankai-serve"
chmod +x "$DEST/bankai" "$DEST/bankai-serve"

echo ""
echo "Installed bankai -> $DEST/bankai"
echo "Installed bankai-serve -> $DEST/bankai-serve"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "NOTE: $DEST is not on your PATH. Add it:  export PATH=\"$DEST:\$PATH\"" ;;
esac

# --- macOS daemon agent ------------------------------------------------------
# The daemon MUST run from the serve-dedicated bankai-serve path. macOS
# Background Task Management SIGKILLs processes whose executable path
# belongs to a hand-installed LaunchAgent it never registered: BTM's
# LoginItems.appex reconciles the ghost job every ~30s and kills the
# running instance (observed as a 42s boot/kill cycle, launchd respawning
# "inefficient"). A distinct serve path + fresh label breaks the stale-path
# match. See issue #31.
if [ "$(uname -s)" = "Darwin" ]; then
  UID_N="$(id -u)"
  REPO="$(pwd)"
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST="$PLIST_DIR/com.bankai.serve.plist"
  LEGACY_LABEL="com.bankai.daemon"

  # migrate away any legacy agent installed under the old name
  launchctl bootout "gui/$UID_N/$LEGACY_LABEL" 2>/dev/null || true
  rm -f "$PLIST_DIR/$LEGACY_LABEL.plist"

  mkdir -p "$PLIST_DIR" "$REPO/.bankai"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bankai.serve</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST/bankai-serve</string>
        <string>serve</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$REPO</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$REPO/.bankai/serve.log</string>
    <key>StandardErrorPath</key>
    <string>$REPO/.bankai/serve.err.log</string>
</dict>
</plist>
PLIST

  # (re)start under the new identity; bootout first so re-installs are clean
  launchctl bootout "gui/$UID_N/com.bankai.serve" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_N" "$PLIST"
  echo "LaunchAgent com.bankai.serve installed and started."
  echo "Daemon logs: $REPO/.bankai/serve.log"
else
  echo "Non-macOS: start the daemon yourself when needed:  bankai serve &"
fi

echo "Run:  bankai --help"
