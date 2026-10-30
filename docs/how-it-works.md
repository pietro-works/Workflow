# How it works

The mechanics behind the hook gate and the installer, plus what the setup does not cover. Everything here was read from the scripts in [`pacs/pacs-hooks/hooks/`](../pacs/pacs-hooks/hooks) and from [`install.sh`](../install.sh).

## The gate, step by step

Three scripts share one marker file at `<project>/.claude/.pacs-registry-read`.

| Script | Event | Behavior |
| :--- | :--- | :--- |
| `pacs-reset-marker.sh` | `SessionStart` | Deletes the marker, unconditionally |
| `pacs-mark-read.sh` | `PostToolUse` on `Read` | Writes a timestamp to the marker when the file just read is exactly this project's `AGENTS.md` |
| `pacs-enforce-read.sh` | `PreToolUse` on `Edit`, `Write`, `MultiEdit` | Exits 2 with an instruction on stderr if the marker is missing |

Exit code 2 is the blocking signal for a `PreToolUse` hook. Claude Code stops the tool call and feeds the stderr text back as the reason, so the agent is told exactly what to do next.

### Which project is "this project"

All three scripts carry the same resolution block, and a test checks that they stay identical. Where the scripts live decides what counts as the project. Installed under `<project>/.claude/hooks/` next to that project's `AGENTS.md`, the project is that one. Anywhere else, which is the global install run in place, the script takes `.cwd` from the payload and climbs from there to the nearest `AGENTS.md` that has registry entries, stopping after the first folder holding a `.git`. If no registry on the way up has entries it uses the nearest `AGENTS.md`, and if there is none the hook does nothing. A relative or missing `cwd` finds nothing.

Because the climb starts wherever `cwd` is, a session that has `cd`'d into a subfolder still resolves the same project, registry and marker. The scripts never fall back to the folder they live in, which for a global install is the PACS repo itself, and they don't trust `CLAUDE_PROJECT_DIR`, because some entrypoints leave it unset.

### What counts as a read

- The path has to match the project's `AGENTS.md` after normalization. Both sides are resolved the same way, so `//`, `..` and a symlinked prefix such as macOS's `/tmp` still count as the same file. The script tries `realpath -m`, then plain `realpath`, then a physical directory lookup. When normalization is in doubt it leaves the path as it is, so the gate can miss but can't match a different file. A path containing a newline never counts. Reading some other `AGENTS.md`, such as a global one or another repo's, does nothing.
- A `Read` with `limit` or `offset` is ignored. Skimming three lines to clear the gate doesn't count.

### When the gate stays out of the way

`pacs-enforce-read.sh` exits 0 without blocking when:

- the project has no `AGENTS.md`, or
- the registry has no entries. An entry is a top-level `PACS####:` key, and commented-out example lines don't match. The script also counts lines starting with `|` anywhere in `AGENTS.md` to recognize legacy table registries, so an empty-registry file with three or more lines of an unrelated markdown table still blocks.

That is why a global install costs nothing in projects that don't use PACS, and why a fresh repo isn't deadlocked by a registry that is still empty.

### Why compaction is covered

`SessionStart` fires on compaction as well as on a fresh start. The reset script doesn't try to detect a summary. It clears the marker every time, so the only way to set it again is a real `Read` call on `AGENTS.md`.

## Why the registry sits in the project's AGENTS.md

The gate looks for the registry in the nearest `AGENTS.md` at or above the payload's `cwd`. The global `~/.claude/AGENTS.md` is only a pointer to `CLAUDE.md` and has no registry, so it never satisfies or triggers the gate. Per-project rules and the registry live in each project's own `AGENTS.md`, while the global rules live in `CLAUDE.md`.

## The installer

`install.sh` works in four steps, and each one is safe to rerun.

1. **Hooks.** It substitutes the bundle's absolute path into [`hooks/settings.hooks.json`](../hooks/settings.hooks.json) and merges the result into `settings.json` with `jq`. An entry is skipped only when the same matcher and command are already present, so existing hooks stay and reruns add nothing. PACS hooks wired from a different location are reported, not removed. An empty `settings.json` is treated as `{}`, invalid JSON is refused, and the file mode is kept.
2. **Command.** It links `pacs` into the bin directory. If something is already there pointing elsewhere, it leaves it alone and says so.
3. **Instructions.** It appends the `## PACS` section of `CLAUDE.md` only when the target file exists and has no such heading.
4. **headroom.** It runs `headroom init -g claude` only with `--with-headroom`, and only if `headroom` is on the PATH.

Each modified file is copied to `<file>.bak.<UTC timestamp>` first. The dry run prints the same plan and writes nothing.

## Known limits

- **The gate proves a read, not understanding.** It makes sure the registry was opened. The report line at the end of a change, naming the rows opened and where the touch-points were confirmed, is what makes the work checkable.
- **Hook commands are unquoted.** A bundle path with spaces would break them, so the installer refuses to `--apply` from one.
- **The marker is per project, not per session.** Two sessions in one project share it, so one session's read unlocks the other. Add `.claude/.pacs-registry-read` to that project's `.gitignore`.
- **Only the three PACS hooks are installed by default.** headroom's entries come from headroom's own installer. [`hooks/headroom.hooks.json`](../hooks/headroom.hooks.json) is a reference copy.
- **Proxy routing is not managed here.** headroom runs a local proxy, and pointing Claude Code at it is a settings matter the installer doesn't read or write.
- **`jq` is required at hook time, on the hook's PATH.** Without it the scripts can't read the payload, fall back to the bundle's own folder, and the gate quietly turns itself off. Reports in the Claude Code issue tracker say the desktop app's PATH often lacks Homebrew, so check that `jq` resolves in your hook environment.
- **The gate follows `cwd`, not the file being edited.** An agent that `cd`s out of a project before editing it walks past the gate, and a nested repo or worktree with its own `.git` counts as a project of its own. With nested registries the nearest populated one wins. Claude Code's hooks reference says `cwd` follows a Bash `cd`, which the climb handles inside a project.
- **Only some write paths are covered.** The matcher is `Edit|Write|MultiEdit`. Per the hooks reference, `NotebookEdit`, shell redirects, `sed -i` and MCP file tools bypass it.
- **Tested from the shell, not inside a live session.** `pacs/test/run_tests.sh` covers `pacs check`. [`pacs/test/run_hook_tests.sh`](../pacs/test/run_hook_tests.sh) covers the path matching in 22 cases, including a PATH with no `realpath`. [`pacs/test/run_hook_scenarios.sh`](../pacs/test/run_hook_scenarios.sh) covers project resolution when `cwd` drifts, in 50 checks. [`tests/run.sh`](../tests/run.sh) runs the installer and the three gate scripts in a throwaway HOME, including the block, allow and block-again-after-reset sequence. CI runs all of it on Linux and macOS.
