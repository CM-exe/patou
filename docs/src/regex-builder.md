# Regex pattern builder

`.patou/config.toml`'s `[commit]`, `[branch]`, and `[tag]` rules are all a
single `pattern` key ([Configuration](./configuration.md)), matched by
**two** separate engines against the exact same bytes: the Rust `regex`
crate (`patou check`) and `grep -E` in the installed shell hooks (see
[How hooks work](./hooks.md)). The tool below builds a pattern visually,
piece by piece, and only ever emits syntax both engines agree on — no
PCRE-only features (non-capturing groups, lazy quantifiers, lookaround,
inline flags) that would work in one and silently misbehave in the other.

Every part of the pattern is editable: add as many pieces as you want, in
any order, nest groups inside groups, add alternatives, and attach a
repeat count to anything. Nothing here is specific to commit messages —
build whatever shape you need for `[commit]`, `[branch]`, or `[tag]`.

<div id="patou-regex-builder"></div>

## How to read the pieces

- **Text** — literal characters. Escaped automatically unless you tick
  "treat as raw regex", which inserts whatever you type unescaped (for
  when you want to hand-write a fragment like `(` or `a{2}` directly).
- **Character set** — a bracket expression (`[...]`). Combine POSIX
  classes (letters, digits, whitespace, …) with your own extra characters
  and optionally negate the whole set.
- **Any char** — `.`, matches one character of any kind.
- **Anchor** — `^`, `$`, or (with a portability warning) `\b`/`\B`.
- **Group** — `(...)`, with one or more `|`-separated alternatives. Each
  alternative is itself a full sequence, so groups can nest.
- **Raw regex** — an escape hatch: whatever you type is inserted
  byte-for-byte, unescaped and unvalidated.

Every piece (except anchors) can carry a repeat count — once, `?`, `*`,
`+`, `{n}`, `{n,}`, or `{n,m}` — all standard POSIX ERE, so they match
identically under `grep -E` and the Rust `regex` crate.

## Why some options are missing on purpose

A few regex features that other online regex builders expose are left out
here deliberately, because `grep -E` (POSIX ERE) can't evaluate them the
same way the Rust `regex` crate can:

- **Non-capturing groups** (`(?:...)`) — not POSIX ERE. Every group this
  tool produces is a plain capturing group `(...)` instead; that changes
  nothing about whether a pattern matches.
- **Lazy quantifiers** (`*?`, `+?`) — POSIX ERE quantifiers are always
  greedy, so only the greedy forms are offered.
- **Lookahead / lookbehind** — unsupported by both `grep -E` and the Rust
  `regex` crate (it never implements backtracking lookaround), so there's
  no way to use them here even via the "raw regex" escape hatch and have
  both engines agree.
- **Inline flags** (`(?i)`, etc.) — `grep -E` has no such syntax, and
  there's nowhere in `config.toml` to carry flags separately. Match case
  explicitly instead, e.g. `[a-zA-Z]` rather than a case-insensitive flag.

`\b`/`\B` (word boundaries) are offered with a warning rather than left
out entirely: they're a GNU `grep` extension that also works with the
Rust `regex` crate, but aren't guaranteed on every `grep` a contributor
might have (notably older BSD/macOS `grep` without GNU extensions). Use
them only if your contributors are on a consistent, known toolchain.

## Using the result

1. Build the pattern above, using **Try it** to check it against a few
   real and a few intentionally-invalid examples.
2. Copy the generated pattern, or the ready-made TOML snippet.
3. Paste it into the matching section of `.patou/config.toml`, keeping
   `pattern` as a single-quoted TOML **literal** string (the default
   presets already use this form) — see
   [Use a TOML literal string](./configuration.md#use-a-toml-literal-string)
   for why that matters.
