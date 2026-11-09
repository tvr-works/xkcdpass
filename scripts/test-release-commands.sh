#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release-version.sh
source "${repo_root}/scripts/release-version.sh"

valid_versions=(
  v0.0.0
  v1.2.3
  v1.2.3-rc.1
  v1.2.3-0.alpha-1+build.001
)
invalid_versions=(
  ""
  1.2.3
  v1.2
  v01.2.3
  v1.02.3
  v1.2.03
  v1.2.3-01
  v1.2.3-rc_1
  "v1.2.3 "
  'v1.2.3;echo unsafe'
)

for version in "${valid_versions[@]}"; do
  validate_release_version "${version}" || fail "valid version was rejected: ${version}"
done
for version in "${invalid_versions[@]}"; do
  if validate_release_version "${version}" 2>/dev/null; then
    fail "invalid version was accepted: ${version}"
  fi
done

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
mkdir "${test_dir}/bin"
mock_log="${test_dir}/gh.log"

cat > "${test_dir}/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash

set -euo pipefail

printf '%s %s %s\n' "${1:-}" "${2:-}" "${3:-}" >> "${MOCK_GH_LOG}"

if [[ "${1:-}" == "release" && "${2:-}" == "view" ]]; then
  [[ $# -eq 9 ]]
  [[ "$3" == "${MOCK_EXPECTED_VERSION:-v1.2.3}" ]]
  [[ "$4" == "--repo" && "$5" == "tvr-works/xkcdpass" ]]
  [[ "$6" == "--json" && "$7" == "isDraft,tagName,url" ]]
  [[ "$8" == "--template" ]]
  [[ "$9" == '{{.tagName}}|{{.isDraft}}|{{.url}}{{"\n"}}' ]]

  case "${MOCK_RELEASE_STATE:-published}" in
    missing)
      echo "release not found" >&2
      exit 1
      ;;
    draft)
      printf '%s|true|https://github.com/tvr-works/xkcdpass/releases/tag/%s\n' "$3" "$3"
      ;;
    published)
      printf '%s|false|https://github.com/tvr-works/xkcdpass/releases/tag/%s\n' \
        "${MOCK_RELEASE_TAG:-$3}" "$3"
      ;;
    *)
      exit 2
      ;;
  esac
elif [[ "${1:-}" == "workflow" && "${2:-}" == "run" ]]; then
  [[ $# -eq 11 ]]
  case "$3" in
    distribution.yml)
      [[ "$4" == "--repo" && "$5" == "tvr-works/xkcdpass" ]]
      [[ "$6" == "--ref" && "$7" == "main" ]]
      [[ "$8" == "-f" && "$9" == "operation=release" ]]
      [[ "${10}" == "-f" && "${11}" == "version=${MOCK_EXPECTED_VERSION:-v1.2.3}" ]]
      ;;
    publish-package.yml)
      [[ "$4" == "--repo" && "$5" == "tvr-works/homebrew-tap" ]]
      [[ "$6" == "--ref" && "$7" == "main" ]]
      [[ "$8" == "-f" && "$9" == "package=xkcdpass" ]]
      [[ "${10}" == "-f" && "${11}" == "version=${MOCK_EXPECTED_VERSION:-v1.2.3}" ]]
      ;;
    *)
      exit 3
      ;;
  esac
else
  exit 4
fi
MOCK_GH
chmod +x "${test_dir}/bin/gh"

export MOCK_GH_LOG="${mock_log}"
export PATH="${test_dir}/bin:${PATH}"

: > "${mock_log}"
just --quiet --justfile "${repo_root}/justfile" release v1.2.3 >/dev/null
[[ "$(sed -n '1p' "${mock_log}")" == "workflow run distribution.yml" ]] ||
  fail "source release command dispatched the wrong workflow"
[[ "$(wc -l < "${mock_log}" | tr -d ' ')" == "1" ]] ||
  fail "source release command made an unexpected gh call"

: > "${mock_log}"
if "${repo_root}/scripts/release.sh" v1.2 >/dev/null 2>&1; then
  fail "source release command accepted an invalid version"
fi
[[ ! -s "${mock_log}" ]] || fail "invalid source release invoked gh"

: > "${mock_log}"
if just --quiet --justfile "${repo_root}/justfile" release 'v1.2.3;echo unsafe' >/dev/null 2>&1; then
  fail "source release recipe accepted an unsafe version"
fi
[[ ! -s "${mock_log}" ]] || fail "unsafe source release input invoked gh"

: > "${mock_log}"
MOCK_RELEASE_STATE=draft \
  "${repo_root}/scripts/publish-homebrew.sh" v1.2.3 >/dev/null 2>&1 &&
  fail "Homebrew command accepted a draft release"
[[ "$(sed -n '1p' "${mock_log}")" == "release view v1.2.3" ]] ||
  fail "Homebrew command did not check the source release"
[[ "$(wc -l < "${mock_log}" | tr -d ' ')" == "1" ]] ||
  fail "Homebrew command dispatched after finding a draft"

: > "${mock_log}"
MOCK_RELEASE_STATE=missing \
  "${repo_root}/scripts/publish-homebrew.sh" v1.2.3 >/dev/null 2>&1 &&
  fail "Homebrew command accepted a missing release"
[[ "$(wc -l < "${mock_log}" | tr -d ' ')" == "1" ]] ||
  fail "Homebrew command dispatched after failing to find the release"

: > "${mock_log}"
MOCK_RELEASE_STATE=published MOCK_RELEASE_TAG=v1.2.4 \
  "${repo_root}/scripts/publish-homebrew.sh" v1.2.3 >/dev/null 2>&1 &&
  fail "Homebrew command accepted a mismatched release tag"
[[ "$(wc -l < "${mock_log}" | tr -d ' ')" == "1" ]] ||
  fail "Homebrew command dispatched after finding a mismatched release"

: > "${mock_log}"
MOCK_RELEASE_STATE=published \
  just --quiet --justfile "${repo_root}/justfile" publish-homebrew v1.2.3 >/dev/null
[[ "$(sed -n '1p' "${mock_log}")" == "release view v1.2.3" ]] ||
  fail "Homebrew command did not check the source release first"
[[ "$(sed -n '2p' "${mock_log}")" == "workflow run publish-package.yml" ]] ||
  fail "Homebrew command dispatched the wrong workflow"
[[ "$(wc -l < "${mock_log}" | tr -d ' ')" == "2" ]] ||
  fail "Homebrew command made an unexpected gh call"

echo "release command tests passed"
