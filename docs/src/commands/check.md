# `patou check`

```bash
patou check [message-file]
patou check -r|--raw <message>...
```

Validates a commit message against the `[commit]` rule in
`.patou/config.toml`.

> `patou check` only covers `[commit]`. The `[branch]` and `[tag]` rules
> (added by `patou init -b`/`-t`/`-a`, see [Configuration](../configuration.md))
> have no `patou check` equivalent — they're validated only by their own
> hook (`pre-commit`/`pre-push` respectively).

- `message-file` — path to a file containing the commit message, in the
  same format Git passes to a `commit-msg` hook (the first argument,
  `$1`). Optional.
- `-r`/`--raw <message>...` — check a literal message instead of a file.
  Everything after `-r`/`--raw` is taken as the message: pass it quoted
  as one argument (`patou check -r "feat: add x"`) or unquoted as
  several, which get joined back into one message with spaces
  (`patou check -r feat: add x`). Mutually exclusive with `message-file`.

## Exit behavior

- Exits `0` and prints `commit message OK` if the subject matches the
  configured pattern.
- Exits `1` and prints the rejected subject plus the expected pattern to
  stderr if it doesn't match.
- Exits `0` and prints a note if no `message-file` was given, or if
  `.patou/config.toml` has no `[commit]` rule — there's nothing to
  validate.
- Exits `1` with an error if `.patou/config.toml` is missing (repository
  not initialized), invalid TOML, or the configured pattern isn't a valid
  regex.

## Where it's used

- **Not** by the Git hook — `.patou/hooks/commit-msg` validates directly
  in shell, without calling `patou`, so it works without a global install
  (see [How hooks work](../hooks.md)).
- Manually, to test a rule against a candidate message.
- In CI, where `patou` can be installed as part of the pipeline, as an
  extra validation layer independent of the client-side hook.

## Example

```bash
echo "fix(parser): handle empty input" > msg.txt
patou check msg.txt
# commit message OK
```

```bash
patou check -r "fix(parser): handle empty input"
# commit message OK
```
