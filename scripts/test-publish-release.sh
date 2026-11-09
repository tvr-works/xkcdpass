#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
publisher="${repo_root}/.github/scripts/publish-release.sh"
fake_gh="${repo_root}/scripts/testdata/fake-gh-release.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

version="v1.2.3"
target_sha="1111111111111111111111111111111111111111"
other_sha="2222222222222222222222222222222222222222"
release_note_marker='<!-- xkcdpass distribution workflow -->'
system_path="${PATH}"

asset_digest() {
  local path="$1"
  local digest

  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "${path}" | awk '{print $1}')"
  else
    digest="$(shasum -a 256 "${path}" | awk '{print $1}')"
  fi
  printf 'sha256:%s\n' "${digest}"
}

create_artifacts() {
  printf 'darwin archive\n' > "${case_dist}/xkcdpass_${version}_darwin_arm64.tar.gz"
  printf 'linux archive\n' > "${case_dist}/xkcdpass_${version}_linux_amd64.tar.gz"
  (
    cd "${case_dist}"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum \
        "xkcdpass_${version}_darwin_arm64.tar.gz" \
        "xkcdpass_${version}_linux_amd64.tar.gz" > checksums.txt
    else
      shasum -a 256 \
        "xkcdpass_${version}_darwin_arm64.tar.gz" \
        "xkcdpass_${version}_linux_amd64.tar.gz" > checksums.txt
    fi
  )
}

new_case() {
  case_dir="${test_root}/$1"
  case_state="${case_dir}/state"
  case_dist="${case_dir}/dist"
  case_runner_temp="${case_dir}/runner"
  case_log="${case_dir}/mutations.log"
  case_bin="${case_dir}/bin"
  mkdir -p "${case_state}" "${case_dist}" "${case_runner_temp}" "${case_bin}"
  cp "${fake_gh}" "${case_bin}/gh"
  chmod +x "${case_bin}/gh"
  : > "${case_log}"
  create_artifacts
}

seed_release() {
  local draft="$1"
  local target="$2"
  local title="$3"
  local body="$4"
  local prerelease="$5"

  jq -n \
    --arg tag "${version}" \
    --arg target "${target}" \
    --arg title "${title}" \
    --arg body "${body}" \
    --argjson draft "${draft}" \
    --argjson prerelease "${prerelease}" \
    '{tag_name: $tag, target_commitish: $target, name: $title, body: $body,
      draft: $draft, prerelease: $prerelease, assets: []}' > "${case_state}/release.json"
}

seed_tag() {
  local sha="$1"
  jq -n --arg sha "${sha}" '{object: {type: "commit", sha: $sha}}' > "${case_state}/tag.json"
}

add_remote_asset() {
  local name="$1"
  local state="$2"
  local digest="$3"
  local replacement

  replacement="$(mktemp "${case_state}/release.XXXXXX")"
  jq --arg name "${name}" --arg state "${state}" --arg digest "${digest}" \
    '.assets += [{name: $name, state: $state, digest: $digest}]' \
    "${case_state}/release.json" > "${replacement}"
  mv "${replacement}" "${case_state}/release.json"
}

run_publisher() {
  local requested_version="$1"
  GITHUB_REPOSITORY="tvr-works/xkcdpass" \
    MOCK_GH_FAIL_UPLOAD="${mock_fail_upload:-}" \
    MOCK_GH_LOG="${case_log}" \
    MOCK_GH_STATE_DIR="${case_state}" \
    PATH="${case_bin}:${system_path}" \
    RUNNER_TEMP="${case_runner_temp}" \
    "${publisher}" "${requested_version}" "${target_sha}" "${case_dist}"
}

assert_failure() {
  local description="$1"
  shift
  if "$@" > "${case_dir}/stdout" 2> "${case_dir}/stderr"; then
    fail "${description}: expected failure"
  fi
}

assert_log() {
  local expected="$1"
  local actual
  actual="$(cat "${case_log}")"
  [[ "${actual}" == "${expected}" ]] ||
    fail "unexpected mutation log for ${case_dir}: ${actual}"
}

assert_no_publish() {
  if grep -q $'^publish\t' "${case_log}"; then
    fail "failure path published a release in ${case_dir}"
  fi
}

assert_complete_published_release() {
  [[ "$(jq -r '.draft' "${case_state}/release.json")" == "false" ]] ||
    fail "release was not published in ${case_dir}"
  [[ "$(jq -r '.assets | length' "${case_state}/release.json")" == "3" ]] ||
    fail "published release does not have exactly three assets in ${case_dir}"

  local asset remote_state remote_digest local_digest
  for asset in \
    "xkcdpass_${version}_darwin_arm64.tar.gz" \
    "xkcdpass_${version}_linux_amd64.tar.gz" \
    checksums.txt; do
    remote_state="$(jq -r --arg name "${asset}" '.assets[] | select(.name == $name) | .state' "${case_state}/release.json")"
    remote_digest="$(jq -r --arg name "${asset}" '.assets[] | select(.name == $name) | .digest' "${case_state}/release.json")"
    local_digest="$(asset_digest "${case_dist}/${asset}")"
    [[ "${remote_state}" == "uploaded" && "${remote_digest}" == "${local_digest}" ]] ||
      fail "published asset ${asset} does not match the local artifact in ${case_dir}"
  done
}

# A fresh version creates a draft, creates the target tag, uploads only the
# allowlisted assets, and publishes after the final state verification.
new_case fresh
run_publisher "${version}" > "${case_dir}/stdout" 2> "${case_dir}/stderr"
assert_log "$(printf 'create\t%s\t%s\nupload\txkcdpass_%s_darwin_arm64.tar.gz\nupload\txkcdpass_%s_linux_amd64.tar.gz\nupload\tchecksums.txt\npublish\t%s' \
  "${version}" "${target_sha}" "${version}" "${version}" "${version}")"
[[ "$(jq -r '.object.sha' "${case_state}/tag.json")" == "${target_sha}" ]] ||
  fail "fresh release tag targets the wrong commit"
assert_complete_published_release

# A repeat after success is safely idempotent: the immutable published state is
# refused and no create, upload, or edit mutation is attempted.
fresh_log="$(cat "${case_log}")"
assert_failure "published rerun" run_publisher "${version}"
[[ "$(cat "${case_log}")" == "${fresh_log}" ]] ||
  fail "published rerun changed remote state"

# A matching draft retains a fully uploaded matching asset, while mismatched
# and incomplete assets are replaced before publication.
new_case matching-draft
seed_release true "${target_sha}" "${version}" "${release_note_marker}" false
seed_tag "${target_sha}"
darwin_asset="xkcdpass_${version}_darwin_arm64.tar.gz"
linux_asset="xkcdpass_${version}_linux_amd64.tar.gz"
add_remote_asset "${darwin_asset}" uploaded "$(asset_digest "${case_dist}/${darwin_asset}")"
add_remote_asset "${linux_asset}" uploaded 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
add_remote_asset checksums.txt new "$(asset_digest "${case_dist}/checksums.txt")"
run_publisher "${version}" > "${case_dir}/stdout" 2> "${case_dir}/stderr"
assert_log "$(printf 'upload\t%s\nupload\tchecksums.txt\npublish\t%s' "${linux_asset}" "${version}")"
assert_complete_published_release

# Published releases, unexpected assets, and every guarded metadata mismatch
# are rejected before mutation.
new_case published
seed_release false "${target_sha}" "${version}" "${release_note_marker}" false
seed_tag "${target_sha}"
assert_failure "published release" run_publisher "${version}"
assert_log ""

new_case unexpected-asset
seed_release true "${target_sha}" "${version}" "${release_note_marker}" false
seed_tag "${target_sha}"
add_remote_asset notes.txt uploaded 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
assert_failure "unexpected draft asset" run_publisher "${version}"
assert_log ""

reject_draft() {
  local case_name="$1"
  local release_target="$2"
  local title="$3"
  local body="$4"
  local prerelease="$5"
  local tag_target="$6"

  new_case "${case_name}"
  seed_release true "${release_target}" "${title}" "${body}" "${prerelease}"
  seed_tag "${tag_target}"
  assert_failure "${case_name}" run_publisher "${version}"
  assert_log ""
}

reject_draft mismatched-target "${other_sha}" "${version}" "${release_note_marker}" false "${target_sha}"
reject_draft mismatched-title "${target_sha}" "wrong title" "${release_note_marker}" false "${target_sha}"
reject_draft mismatched-notes "${target_sha}" "${version}" "wrong notes" false "${target_sha}"
reject_draft mismatched-prerelease "${target_sha}" "${version}" "${release_note_marker}" true "${target_sha}"
reject_draft mismatched-tag-target "${target_sha}" "${version}" "${release_note_marker}" false "${other_sha}"

# An upload failure leaves a draft and never publishes. A later invocation
# reconciles the partial draft without replacing the already-correct asset.
new_case interrupted-upload
seed_release true "${target_sha}" "${version}" "${release_note_marker}" false
seed_tag "${target_sha}"
mock_fail_upload="${linux_asset}"
assert_failure "interrupted upload" run_publisher "${version}"
assert_no_publish
[[ "$(jq -r '.draft' "${case_state}/release.json")" == "true" ]] ||
  fail "interrupted upload did not leave a draft"
[[ "$(jq -r '.assets | length' "${case_state}/release.json")" == "1" ]] ||
  fail "interrupted upload did not preserve exactly the completed asset"
mock_fail_upload=""
run_publisher "${version}" > "${case_dir}/stdout-rerun" 2> "${case_dir}/stderr-rerun"
[[ "$(grep -c $'^upload\txkcdpass_.*_darwin_arm64.tar.gz$' "${case_log}")" == "1" ]] ||
  fail "reconciliation replaced an already-correct asset"
assert_complete_published_release

# Version validation runs before artifact inspection or any GitHub command.
new_case invalid-version
assert_failure "invalid version" run_publisher v1.2
assert_log ""

echo "release publisher tests passed"
