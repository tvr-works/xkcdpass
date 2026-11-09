# Contributing

## Development setup

This project uses `just` for the common local workflows. Those recipes keep Go's build cache in `.gocache` inside the repo and leave the module cache at Go's configured default.

```sh
just test
just build
just run -- --words 6
```

Local builds report `dev` for `--version`. Distribution builds inject either a development identifier or the requested release tag through the `main.version` linker flag.

If you prefer running Go commands directly, set `GOCACHE` to keep behavior consistent with the `just` tasks:

```sh
GOCACHE=$PWD/.gocache go test ./...
GOCACHE=$PWD/.gocache go build ./cmd/xkcdpass
```

## Tests

Regular tests run with `go test ./...` and include validation of the embedded EFF wordlist. A normal test run checks:

- the list contains exactly 7,776 entries
- entries are lowercase
- entries do not contain surrounding or internal whitespace
- entries are unique

These checks run as normal tests; you do not need to do anything special to enable them.

## Automated validation

GitHub Actions validates pushes on every branch, pull requests targeting `main`, and manual CI runs. The reusable Verification workflow runs the full Linux suite with pinned Go 1.27.3, checks vulnerabilities for `linux/amd64` and `darwin/arm64` with pinned govulncheck, and tests the declared Go 1.26.0 minimum with `GOTOOLCHAIN=local`. Existing formatting, race, vet, ShellCheck, and mocked release-tooling checks remain enabled.

Verification creates unsigned GoReleaser snapshot archives once on Linux. Linux and Apple Silicon macOS jobs execute those same uploaded archives, checking version, generation, help, invalid input, layout, and checksums. Source-only Intel macOS, ARM64 Linux, and Windows targets are cross-compiled. These compile checks do not establish native runtime compatibility. The macOS runner uses macOS 26; confirm macOS 13 separately before relying on the documented minimum OS.

Blacksmith supplies the Ubuntu and Apple Silicon macOS runners. Test, race, vulnerability, and archive-smoke reports are retained for seven days; archives are retained for 14 days, and packaging failures also retain the available `dist` directory. These are workflow artifacts, not published releases. CI has read-only repository permissions and cannot publish tags, releases, or Homebrew updates.

Manual Distribution runs invoke that same Verification workflow. A release cannot reach the existing environment approval until Linux, minimum-compiler, and macOS archive verification all succeed for that run's exact SHA. Homebrew publication remains a separate maintainer checkpoint.

### Repository and Go module identity

Repository operations use `tvr-works/xkcdpass`. The Go module and internal imports intentionally retain `github.com/tvanreenen/xkcdpass`: immutable historical tags declare that path, and versioned Go installs must agree with it. Changing the module would require a separate versioning and compatibility plan; the transfer alone does not authorize rewriting historical tags. Do not recreate the old GitHub repository name because doing so would break the transfer redirect used by direct module downloads. Test both proxy-backed and direct legacy-path installs when changing ownership or release tooling.

## Benchmarks and timing

Benchmarks are opt-in and do not run under a normal `go test ./...`.

To run the benchmark coverage for the startup-sensitive paths:

```sh
GOCACHE=$PWD/.gocache go test -bench . -benchmem ./internal/wordlist ./internal/passphrase
```

This runs:

- `BenchmarkWords`
- `BenchmarkGenerate4Words`

To measure end-to-end CLI startup time locally:

```sh
GOCACHE=$PWD/.gocache go build -o xkcdpass ./cmd/xkcdpass
time sh -c 'i=0; while [ $i -lt 500 ]; do ./xkcdpass >/dev/null; i=$((i+1)); done'
```

The timing loop is only for manual performance checks. It is not part of the normal test suite or distribution workflow.

## Releases

### Repository setup for releases

Repository administrators should keep two release settings configured:

1. Under **Settings → Environments**, create an environment named `release`. Restrict its deployment branches to the default `main` branch and configure the required reviewers. Preventing self-review is recommended when more than one maintainer is available.
2. Under **Settings → General → Releases**, enable release immutability. GitHub applies this only to releases published after the setting is enabled.

Keep the repository's default Actions token permissions read-only. The workflow grants `contents: write` only to the environment-gated publishing job; `GITHUB_TOKEN` is sufficient, and no repository secret or cross-repository token is needed.

### Manual development builds

After the distribution workflow is present on the default branch, open **Actions → Distribution → Run workflow**, select the ref to build, leave the operation set to `build`, and start the run. The same build can be started with GitHub CLI:

```sh
gh workflow run distribution.yml --ref <branch-or-tag> -f operation=build
```

The version input is not required in build mode and is ignored if supplied. When the run succeeds, download the `xkcdpass_dev-<commit-sha>` workflow artifact from its summary page. It contains the `darwin/arm64` and `linux/amd64` archives plus `checksums.txt`, and is retained for 14 days. With GitHub CLI, use `gh run download <run-id> --name xkcdpass_dev-<commit-sha>`.

Use build mode as the release dry run: dispatch it from the intended `main` commit, confirm tests and vet pass, inspect both packaged binaries and `checksums.txt`, and confirm the smoke checks in the log. Release mode runs that same full Verification workflow again with the release version injected.

### Publishing a release

From a current `main` checkout, dispatch the source release with:

```sh
just release v1.2.3
```

Replace the illustrative `v1.2.3` with the version being published. The command validates the version locally and dispatches `distribution.yml` on `main` through your existing GitHub CLI login. You can also open **Actions → Distribution → Run workflow**, select `main`, choose `release`, and enter the version. Release versions must be valid v-prefixed Semantic Versions such as `v1.2.3`, `v1.2.3-rc.1`, or `v1.2.3-rc.1+build.2`. Leading zeroes, missing components, whitespace, and unsafe tag characters are rejected before any release write. Release dispatches from branches or tags other than the repository's default branch are also rejected.

After the build artifact is uploaded, the publishing job waits for approval on the `release` environment. Before approving, confirm the requested version, workflow commit, and completed build logs. The publishing job uses only the archives and checksum file uploaded by that same workflow run. It does not rebuild, download from an earlier run, update another repository, or use checkout credentials to push.

Publication is draft-first. The job preflights the version's release and tag state, creates a generated-notes draft targeted at the exact workflow commit when none exists, uploads the expected assets, verifies their SHA-256 digests and complete asset set, and only then publishes. Semantic Version prereleases are marked as GitHub prereleases. Once published, the workflow treats the release as immutable and refuses to update it; repository release immutability locks its tag and assets on GitHub as well.

Runs for the same release version are queued instead of canceled. If a run stops after creating a draft or uploading only some assets, rerun the same version from the same `main` commit. A matching draft is reconciled: identical assets are retained and missing or incomplete assets are replaced from the new run before publication. The workflow refuses an existing published release, an unexpected draft asset, a draft with different metadata or target commit, or a tag pointing at another commit. Inspect such state manually; only delete an unpublished draft or tag after confirming it is safe to abandon, then dispatch again.

For extra validation, an optional release sequence is:

1. Dispatch an illustrative prerelease such as `v1.2.3-rc.1`, approve it, and test the published prerelease assets.
2. Dispatch its stable counterpart, such as `v1.2.3`, from the desired current `main` commit and approve it independently.

Each version receives its own tag, assets, release notes, approval, and non-canceling concurrency group.

### Publishing the Homebrew update

Wait until the source release is published, then run the separate Homebrew checkpoint:

```sh
just publish-homebrew v1.2.3
```

Replace the illustrative `v1.2.3` with the published source version. The command confirms that GitHub reports a published, non-draft `tvr-works/xkcdpass` release for that tag, then dispatches `tvr-works/homebrew-tap/.github/workflows/publish-package.yml` on the tap's `main` branch with `package=xkcdpass` and the version. It uses your existing GitHub CLI login; this repository stores no tap credential. The distribution workflow remains independent and never dispatches the tap workflow.

The tap verifies the published archives and `checksums.txt`, renders the formula change, runs the Homebrew checks, and opens or reuses its pull request. Follow the dispatched run with:

```sh
gh run list --repo tvr-works/homebrew-tap --workflow publish-package.yml
```

If the source release is still a draft or missing, finish or rerun `just release` and wait for publication before retrying the Homebrew command. If tap verification finds a problem in an immutable source release, publish a new version and dispatch that version instead. For a transient tap or Homebrew failure, rerun `just publish-homebrew` with the same published version; do not rebuild or edit the source release.
