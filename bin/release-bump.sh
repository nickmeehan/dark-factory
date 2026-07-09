#!/usr/bin/env bash
# Writes the released version into .claude-plugin/plugin.json.
# Called by semantic-release (see release.config.js).
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 MAJOR.MINOR.PATCH" >&2
  exit 64
fi

root="$(git rev-parse --show-toplevel)"
# ponytail: ruby instead of jq — jq isn't guaranteed locally, ruby is the repo's scripting language
# Single plugin, so the marketplace version tracks the plugin version in lockstep.
ruby -rjson -e '
  version = ARGV.shift
  plugin, marketplace = ARGV
  j = JSON.parse(File.read(plugin))
  j["version"] = version
  File.write(plugin, JSON.pretty_generate(j) + "\n")
  m = JSON.parse(File.read(marketplace))
  m["metadata"]["version"] = version
  File.write(marketplace, JSON.pretty_generate(m) + "\n")
' "$1" "$root/.claude-plugin/plugin.json" "$root/.claude-plugin/marketplace.json"

echo "release-bump: fabro + marketplace $1"
