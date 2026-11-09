#!/usr/bin/env bash

# This is the repository's authoritative release-version policy. Every release
# entry point sources this file before it reads or changes remote release state.
xkcdpass_release_semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'

validate_release_version() {
  local version="${1:-}"
  if [[ ! "${version}" =~ ${xkcdpass_release_semver} ]]; then
    echo "release version must match vMAJOR.MINOR.PATCH with valid optional Semantic Version prerelease or build metadata" >&2
    return 1
  fi
}

# An empty release version selects a development snapshot for the exact commit.
distribution_version() {
  local requested_version="$1"
  local sha="$2"
  [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid distribution commit" >&2; return 1; }
  if [[ -z "${requested_version}" ]]; then
    printf 'dev-%s\n' "${sha}"
  else
    validate_release_version "${requested_version}" || return 1
    printf '%s\n' "${requested_version}"
  fi
}
