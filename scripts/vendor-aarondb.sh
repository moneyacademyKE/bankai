#!/bin/sh
# Usage: sh scripts/vendor-aarondb.sh check
#        sh scripts/vendor-aarondb.sh update /path/to/aarondb COMMIT
# Updates preserve the old vendor and provenance under .git/vendor-backups.
set -eu
cd "$(git rev-parse --show-toplevel)"
record=scripts/aarondb.provenance
check() {
  expected=$(sed -n 's/^tree=//p' "$record")
  test -n "$expected"
  index=$(mktemp)
  rm "$index"
  trap 'rm -f "$index"' EXIT HUP INT TERM
  GIT_INDEX_FILE="$index" git read-tree HEAD
  GIT_INDEX_FILE="$index" git add -A -- aarondb
  root=$(GIT_INDEX_FILE="$index" git write-tree)
  actual=$(git rev-parse "$root:aarondb")
  test "$actual" = "$expected" || {
    echo "AaronDB vendor drift: expected $expected, found $actual" >&2
    exit 1
  }
  echo "AaronDB vendor tree verified: $actual"
}
case "${1:-check}" in
  check) check ;;
  update)
    test "$#" = 3 || { echo 'Expected source repository and commit' >&2; exit 1; }
    check
    source=$(cd "$2" && pwd)
    commit=$(git -C "$source" rev-parse "$3^{commit}")
    tree=$(git -C "$source" rev-parse "$commit^{tree}")
    backup=$(mktemp -d "$(git rev-parse --git-dir)/vendor-backup.XXXXXX")
    mkdir "$backup/new"
    git -C "$source" archive --format=tar "$commit" > "$backup/source.tar"
    tar -xf "$backup/source.tar" -C "$backup/new"
    test -f "$backup/new/gleam.toml"
    cp "$record" "$backup/provenance"
    mv aarondb "$backup/aarondb"
    mv "$backup/new" aarondb
    printf 'commit=%s\ntree=%s\n' "$commit" "$tree" > "$record"
    check
    echo "Prior vendor preserved in $backup; running downstream compatibility gate"
    make test
    ;;
  *) echo 'Expected check or update' >&2; exit 1 ;;
esac
