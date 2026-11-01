#!/usr/bin/env bash
# Prepare an App Store / TestFlight build: scripts/set-version.sh 1.1.0 [build]
#
# Writes the version into Configs/Version.xcconfig — MARKETING_VERSION as given,
# CURRENT_PROJECT_VERSION as the next build counter (or an explicit higher one).
# Commits, CI runs and GitHub tags do not determine the App Store version.
set -euo pipefail

version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
build_pattern='^[1-9][0-9]{0,17}$'
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: scripts/set-version.sh <major.minor.patch> [higher-build-number] | --check" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
file="${VERSION_FILE:-$root/Configs/Version.xcconfig}"
current_version="$(sed -nE 's/^MARKETING_VERSION = (.*)$/\1/p' "$file")"
current_build="$(sed -nE 's/^CURRENT_PROJECT_VERSION = (.*)$/\1/p' "$file")"
if [[ ! "$current_version" =~ $version_pattern || ! "$current_build" =~ $build_pattern ]]; then
  echo "set-version: $file must contain one valid marketing version and one positive build number" >&2
  exit 1
fi

if [[ $# -eq 1 && "$1" == --check ]]; then
  echo "Actovia $current_version ($current_build)"
  exit 0
fi

version="$1"
build="${2:-$((current_build + 1))}"
if [[ ! "$version" =~ $version_pattern || ! "$build" =~ $build_pattern ]]; then
  echo "set-version: use major.minor.patch and a positive integer build number, without leading zeroes" >&2
  exit 2
fi
if [[ "$build" -le "$current_build" ]]; then
  echo "set-version: build $build must be greater than the current build $current_build" >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed -E \
  -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" \
  "$file" >"$tmp"
cat "$tmp" >"$file"

if ! grep -qx "MARKETING_VERSION = $version" "$file" \
  || ! grep -qx "CURRENT_PROJECT_VERSION = $build" "$file"; then
  echo "set-version: $file does not hold exactly 'MARKETING_VERSION = $version' and 'CURRENT_PROJECT_VERSION = $build' after writing; check its format" >&2
  exit 1
fi
