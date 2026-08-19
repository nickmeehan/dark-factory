#!/usr/bin/env bash
# Mirror the Fabro docs (docs.fabro.sh) into fabro-docs/ as raw markdown.
# Re-run any time to refresh; git diff shows what changed upstream.
#
# The fetch stages into a temp tree and only lands on fabro-docs/ once every
# page has arrived, so a half-finished run can't leave a truncated mirror
# behind. Pages upstream has dropped are pruned, since a mirror that only ever
# grows drifts just as badly as one that never syncs — but a bad or truncated
# llms.txt would read as "everything was deleted", so the prune is capped at
# PRUNE_LIMIT percent of the mirror and aborts above that.
set -euo pipefail
cd "$(dirname "$0")/.."

PRUNE_LIMIT=${PRUNE_LIMIT:-10}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

curl -fsSL https://docs.fabro.sh/llms.txt -o "$stage/llms.txt"

grep -oE 'https://docs\.fabro\.sh/[^ )]+\.(md|yaml)' "$stage/llms.txt" | sort -u |
  STAGE="$stage" xargs -P 8 -I{} sh -c '
    url="{}"
    path="$STAGE/${url#https://docs.fabro.sh/}"
    mkdir -p "${path%/*}"
    curl -fsSL --retry 2 "$url" -o "$path" && echo "${path#"$STAGE"/}"
  '

# curl -f writes a zero-byte file before it learns the response was an error.
if find "$stage" -type f -empty | grep -q .; then
  echo "sync-docs: upstream returned empty pages, aborting" >&2
  find "$stage" -type f -empty | sed "s|^$stage/|  |" >&2
  exit 1
fi

list() { (cd "$1" && find . -type f | sed 's|^\./||' | sort); }
count() { printf '%s' "${1:-}" | grep -c . || true; }

old=''
[ -d fabro-docs ] && old=$(list fabro-docs)
new=$(list "$stage")
gone=$(comm -23 <(printf '%s\n' "$old") <(printf '%s\n' "$new") | grep -v '^$' || true)

old_count=$(count "$old")
gone_count=$(count "$gone")
if [ "$old_count" -gt 0 ] && [ "$gone_count" -gt $((old_count * PRUNE_LIMIT / 100)) ]; then
  echo "sync-docs: $gone_count of $old_count pages would be pruned (limit ${PRUNE_LIMIT}%)," >&2
  echo "  which looks like a bad upstream index rather than real deletions. Aborting." >&2
  echo "  Re-run with PRUNE_LIMIT=100 if the removals are genuine." >&2
  exit 1
fi

if [ -n "$gone" ]; then
  while IFS= read -r page; do
    rm -f "fabro-docs/$page"
  done <<<"$gone"
fi

mkdir -p fabro-docs
cp -a "$stage/." fabro-docs/
find fabro-docs -mindepth 1 -type d -empty -delete

echo "Synced $(find fabro-docs -name '*.md' | wc -l | tr -d ' ') pages, pruned $gone_count."
