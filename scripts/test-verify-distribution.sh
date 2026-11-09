#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <version> <artifact-directory>" >&2; exit 1; }
version="$1"
artifacts="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

expect_failure() {
  local expected="$1"
  if "${script_dir}/verify-distribution.sh" "${version}" "${test_dir}/dist" > "${test_dir}/log" 2>&1; then
    echo "invalid distribution was accepted: ${expected}" >&2
    exit 1
  fi
  grep -q "${expected}" "${test_dir}/log" || { cat "${test_dir}/log" >&2; exit 1; }
}

cp -R "${artifacts}" "${test_dir}/dist"
rm "${test_dir}/dist/checksums.txt"
expect_failure 'missing distribution checksum'

cp "${artifacts}/checksums.txt" "${test_dir}/dist/checksums.txt"
sed 's/^[0-9a-f]/z/' "${artifacts}/checksums.txt" > "${test_dir}/dist/checksums.txt"
expect_failure 'malformed entry'

cp "${artifacts}/checksums.txt" "${test_dir}/dist/checksums.txt"
archive="xkcdpass_${version}_darwin_arm64.tar.gz"
mkdir "${test_dir}/invalid"
printf 'unexpected\n' > "${test_dir}/invalid/unexpected"
tar -czf "${test_dir}/dist/${archive}" -C "${test_dir}/invalid" unexpected
expect_failure 'unexpected archive contents'

echo 'distribution verifier rejection tests passed'
