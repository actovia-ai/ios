#!/usr/bin/env bash
# Called by semantic-release (.releaserc.json, prepareCmd):  scripts/set-version.sh 1.1.0
#
# Writes the version into Configs/Version.xcconfig — MARKETING_VERSION as given,
# CURRENT_PROJECT_VERSION as the commit count the release commit will have, so the
# build number only ever grows. Commits and tags nothing; semantic-release does.
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/set-version.sh <major.minor.patch>" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
file="${VERSION_FILE:-$root/Configs/Version.xcconfig}"
build=$(( $(git -C "$root" rev-list --count HEAD) + 1 ))

tmp="$(mktemp)"
sed -E \
  -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" \
  "$file" >"$tmp"
cat "$tmp" >"$file"
rm -f "$tmp"

if ! grep -qx "MARKETING_VERSION = $version" "$file" \
  || ! grep -qx "CURRENT_PROJECT_VERSION = $build" "$file"; then
  echo "set-version: $file does not hold exactly 'MARKETING_VERSION = $version' and 'CURRENT_PROJECT_VERSION = $build' after writing; check its format" >&2
  exit 1
fi
