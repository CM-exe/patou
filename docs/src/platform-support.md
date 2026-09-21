# Platform support

Patou is designed to work the same way on Linux, macOS, and Windows. The
table below reflects what's actually been verified versus what follows
from the design (POSIX shell + `git`'s own documented hook-execution
behavior) but hasn't been run on real hardware yet.

| Platform                     | `commit-msg`/`pre-commit`/`pre-push` hook enforcement | `install` activation |
| ----------------------------- | ------------------------------ | ---------------------- |
| Linux                         | ✅ Tested                      | ✅ Tested (`.patou/install`) |
| macOS                         | ✅ Expected to work (untested)  | ✅ Expected to work (untested) |
| Windows, via Git for Windows   | ✅ Expected to work (untested)  | ✅ `.patou/install.cmd` or `.patou/install.ps1` |
| Windows, via Git Bash          | ✅ Expected to work (untested)  | ✅ `.patou/install` also works |

## Why the hooks themselves should work everywhere Git does

Git for Windows executes hook scripts (shebang `#!/bin/sh` files) through
its bundled MSYS `sh`, the same mechanism tools like Husky rely on. Since
`.patou/hooks/commit-msg`, `.patou/hooks/pre-commit`, and
`.patou/hooks/pre-push` are all plain POSIX shell using only `grep`,
`sed`, `awk`, and parameter expansion — no GNU-specific flags — they
should run identically wherever Git itself runs hooks. This hasn't been
verified on an actual Windows machine; if you hit an issue, please open
one.

## Why `install` needs a platform-specific script

`.patou/install` is a shell script; it's not runnable directly from a
plain `cmd.exe` or PowerShell prompt (no shebang support there). That's
why `patou init` also generates `.patou/install.cmd` and
`.patou/install.ps1` — same single `git config core.hooksPath` call,
native to each shell.

## Known caveat: PowerShell execution policy

PowerShell's default execution policy on many machines (`Restricted`)
blocks running local `.ps1` scripts, signed or not. If
`.\.patou\install.ps1` is refused:

```powershell
powershell -ExecutionPolicy Bypass -File .patou\install.ps1
```

or adjust the machine's execution policy. Patou doesn't try to work
around this from inside the script — silently bypassing a security
setting isn't something a setup script should do on your behalf.
