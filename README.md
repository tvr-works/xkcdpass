# xkcdpass

![xkcd #936: Password Strength](https://imgs.xkcd.com/comics/password_strength.png)

[Original comic](https://xkcd.com/936/) by Randall Munroe (xkcd, CC BY-NC 2.5).

`xkcdpass` is a small Go CLI that generates xkcd-style passphrases from the embedded EFF large wordlist using cryptographically secure randomness.

By default, it prints 4 random lowercase words concatenated with no separator, in the style of `correcthorsebatterystaple`.

The comic is a simple lesson in information theory: what feels obscure is not always hard to guess. Counterintuitive as it may seem, a few memorable words from a known list can be stronger than the convoluted strings typical password rules require.

## Installation

On supported published platforms, install with Homebrew:

```sh
brew install tvr-works/tap/xkcdpass
```

Published Homebrew release artifacts are currently available for:

- macOS 13 Ventura or later on Apple Silicon (`darwin/arm64`)
- Linux x86_64 (`linux/amd64`), including typical x86_64 WSL environments

For other platforms, build from source locally:

- macOS Intel (`darwin/amd64`)
- Linux ARM64 (`linux/arm64`)
- Windows native

```sh
go build -o xkcdpass ./cmd/xkcdpass
```

The repository is maintained at [tvr-works/xkcdpass](https://github.com/tvr-works/xkcdpass).
The Go module remains `github.com/tvanreenen/xkcdpass` to preserve compatibility
with existing versions. For a versioned Go install, use
`go install github.com/tvanreenen/xkcdpass/cmd/xkcdpass@v0.2.1`.
The organization path is the repository location, not a replacement module path.

## Usage

```sh
xkcdpass
xkcdpass --words 6
xkcdpass --separator -
xkcdpass --separator _
```

`--words` accepts values from 1 through 100 (default: 4). The upper bound keeps entropy work and output allocation bounded; 100 words from the embedded list already represent roughly 1,290 bits of search space, far beyond practical passphrase use.

Sample output (default: no separator):

```text
washroomunquotedzebravelocity
```

Hyphenated (optional; easier to read or type):

```sh
xkcdpass --separator -
```

```text
washroom-unquoted-zebra-velocity
```

## Security model

- **Entropy source:** Go's `crypto/rand`, backed by the operating system CSPRNG—not `math/rand`, which is unsuitable for secrets.
- **Uniform words:** Each word is an independent, uniformly random draw from the full embedded list (the same word may appear more than once). Indices come from `crypto/rand.Int`, which avoids modulo bias you get when shrinking random bytes with `% len(list)` and the list length is not a power of two.
- **Flat phrase space:** No templates, grammatical rules, or frequency weighting—those steer output toward a smaller or more predictable set of phrases than uniform words from the whole list.
- **Formatting:** Lowercase words are fixed; an optional separator between words does not add entropy.

### Passphrase strength

The EFF large wordlist is public, so strength is quoted the way passphrase tools usually do: treat the list and the number of words as known, and measure what is left to guess—the specific sequence of words. Each independent uniform word adds about 12.9 bits (`log2(7776)`). For *n* words, that is *n* times as much altogether (`log2(7776^n)` bits).

Examples with the embedded 7,776-word list and a known word count:

- 4 words: about 51.7 bits
- 6 words: about 77.6 bits

Use `--words 6` for stronger real-world usage.

For development and release workflows, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Wordlist attribution

The embedded wordlist is based on the EFF large wordlist for passphrases:

- Source: [EFF Large Wordlist for Passphrases](https://www.eff.org/document/passphrase-wordlists)
- File: [eff_large_wordlist.txt](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution details.
