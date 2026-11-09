#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  fail "usage: $0 <version> [artifact-directory]"
fi

version="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${2:-${repo_root}/dist}"
binary_name="xkcdpass"
archives=(
  "${binary_name}_${version}_darwin_arm64.tar.gz"
  "${binary_name}_${version}_linux_amd64.tar.gz"
)

for archive in "${archives[@]}"; do
  archive_base="${archive%.tar.gz}"
  archive_path="${dist_dir}/${archive}"
  [[ -f "${archive_path}" ]] || fail "missing distribution archive: ${archive_path}"

  actual_entries="$(tar -tzf "${archive_path}" | LC_ALL=C sort)"
  expected_entries="${archive_base}/${binary_name}"
  [[ "${actual_entries}" == "${expected_entries}" ]] ||
    fail "unexpected archive contents for ${archive}: ${actual_entries}"
done

[[ -f "${dist_dir}/checksums.txt" ]] ||
  fail "missing distribution checksum file: ${dist_dir}/checksums.txt"

while IFS= read -r checksum_line || [[ -n "${checksum_line}" ]]; do
  [[ "${checksum_line}" =~ ^[0-9a-f]{64}\ \ [0-9A-Za-z._+-]+$ ]] ||
    fail "checksums.txt contains a malformed entry"
done < "${dist_dir}/checksums.txt"

(
  cd "${dist_dir}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check checksums.txt
  else
    shasum -a 256 --check checksums.txt
  fi
)

actual_checksum_entries="$(awk '{print $2}' "${dist_dir}/checksums.txt" | LC_ALL=C sort)"
expected_checksum_entries="$(printf '%s\n' "${archives[@]}" | LC_ALL=C sort)"
[[ "${actual_checksum_entries}" == "${expected_checksum_entries}" ]] ||
  fail "checksums.txt does not cover exactly the supported platform archives"

verify_dir="$(mktemp -d)"
trap 'rm -rf "${verify_dir}"' EXIT
for archive in "${archives[@]}"; do
  tar -C "${verify_dir}" -xzf "${dist_dir}/${archive}"
  binary="${verify_dir}/${archive%.tar.gz}/${binary_name}"
  [[ -f "${binary}" && ! -L "${binary}" && -x "${binary}" ]] ||
    fail "archive must contain an executable regular file: ${archive}"
done

darwin_binary="${verify_dir}/${binary_name}_${version}_darwin_arm64/${binary_name}"
linux_binary="${verify_dir}/${binary_name}_${version}_linux_amd64/${binary_name}"
darwin_description="$(file "${darwin_binary}")"
linux_description="$(file "${linux_binary}")"
[[ "${darwin_description}" == *"Mach-O 64-bit"* && "${darwin_description}" == *"arm64"* ]] ||
  fail "unexpected darwin/arm64 binary format: ${darwin_description}"
[[ "${linux_description}" == *"ELF 64-bit LSB executable, x86-64"* ]] ||
  fail "unexpected linux/amd64 binary format: ${linux_description}"

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    smoke_binary="${darwin_binary}"
    ;;
  Linux/x86_64)
    smoke_binary="${linux_binary}"
    ;;
  *)
    fail "artifact execution smoke checks are not supported on this host"
    ;;
esac

actual_version="$("${smoke_binary}" --version)"
[[ "${actual_version}" == "${version}" ]] ||
  fail "version smoke check returned ${actual_version}, expected ${version}"

generated="$("${smoke_binary}" --words 3 --separator /)"
[[ "${generated}" =~ ^[a-z]+/[a-z]+/[a-z]+$ ]] ||
  fail "generation smoke check returned unexpected output: ${generated}"

"${smoke_binary}" --help > "${verify_dir}/help.stdout" 2> "${verify_dir}/help.stderr"
[[ ! -s "${verify_dir}/help.stdout" ]] || fail "help wrote unexpected stdout"
grep -q 'Usage:' "${verify_dir}/help.stderr" || fail "help did not include usage"

status=0
"${smoke_binary}" --words 0 > "${verify_dir}/invalid.stdout" 2> "${verify_dir}/invalid.stderr" || status=$?
[[ ${status} -eq 2 && ! -s "${verify_dir}/invalid.stdout" ]] || fail "invalid input did not fail with exit 2"
grep -q 'words must be at least 1' "${verify_dir}/invalid.stderr" || fail "invalid input did not explain the error"
echo "Verified ${version} archives and native $(uname -s)/$(uname -m) execution"
