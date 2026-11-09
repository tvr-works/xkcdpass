#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-version.sh
source "${script_dir}/release-version.sh"

if [[ $# -ne 1 ]]; then
  fail "usage: $0 <v-prefixed-version>"
fi

version="$1"
validate_release_version "${version}" || exit 1
command -v gh >/dev/null 2>&1 || fail "gh CLI is required"

gh workflow run distribution.yml \
  --repo tvr-works/xkcdpass \
  --ref main \
  -f operation=release \
  -f version="${version}"

echo "Dispatched the xkcdpass source release for ${version}."
echo "Follow it with: gh run list --repo tvr-works/xkcdpass --workflow distribution.yml"
