# ai.bat

A single-file Windows launcher for terminal AI coding agents. Run it in any project
folder and it walks you through the flags for whichever CLI you pick, shows the final
command, and launches it.

Supports **Claude Code**, **Codex** (OpenAI), **Gemini** (Google) and **Antigravity**
(`agy`). No dependencies beyond the CLI you want to use — it's plain batch.

```
  AI Launcher
============================================================

--- Select AI ---
  [1] Claude       (Anthropic - full agentic CLI)
  [2] Codex        (OpenAI - codex CLI, supports --yolo)
  [3] Gemini       (Google - gemini CLI, supports --yolo)
  [4] Antigravity  (Google - agy terminal agent)

  [F] Fix Environment (set git-bash + PATH permanently)
  [Q] Quit
```

## Install

1. Drop `ai.bat` anywhere (a tools folder, or the repo you work in).
2. Double-click it, or run `ai` from a terminal.
3. Optional: pick **[F] Fix Environment** once. It stores
   `CLAUDE_CODE_GIT_BASH_PATH` and adds the script's folder to your user `PATH`,
   so `ai` works from anywhere.

The script `cd`s to its own folder on start, so the agent's working directory is
wherever `ai.bat` lives.

## Requirements

- Windows with `cmd.exe`
- At least one agent CLI on `PATH`: `claude`, `codex`, `gemini`, or `agy`
- **Git Bash** if you use Claude Code — the script auto-detects it in the usual
  install locations (`%LOCALAPPDATA%\Programs\Git`, `Program Files`, scoop, or
  anything `where bash.exe` finds) and sets `CLAUDE_CODE_GIT_BASH_PATH` for you

## What the Claude menu exposes

Model · effort level · permission mode · session (new / continue / resume / fork /
from PR) · verbose & debug · extra working dirs · system prompt (append or replace) ·
MCP config · tool restrictions · Chrome integration · git worktree (+ tmux) ·
startup mode (`--bare`, `--safe-mode`) · IDE attach.

Model option **[8]** queries `https://api.anthropic.com/v1/models` for the models your
account can actually use. It needs `ANTHROPIC_API_KEY` in your environment (or an
`apiKey` in `%APPDATA%\claude\config.json`); without one it just prints a static list.
The key is only read at runtime and never stored by this script.

At the end you get a confirmation screen with the assembled command, and **[E]** lets
you hand-edit it before launching.

## ⚠️ Default is `--dangerously-skip-permissions`

Pressing Enter through every Claude prompt launches with **all permission checks
bypassed** — the agent can run any command in that folder without asking. That's a
deliberate choice for a trusted local repo; it is not a safe default for code you
don't trust. Pick permission mode **[4] manual** (or `[5] plan`) if you want to be
asked. The Codex and Gemini menus have equivalent `--yolo` options, marked
`[DANGEROUS]`.

## Multiple Claude accounts

The account menu points `CLAUDE_CONFIG_DIR` at `%USERPROFILE%\.claude-acc1` or
`.claude-acc2`, so two logins can coexist without re-authenticating. Run **[A] Auth
Setup** once to log both in — the second one is easier in a different browser, since
the OAuth flow follows whichever browser is already signed in. Each account must be
your own; check your provider's terms before using this to work around usage limits.

No credentials live in this repo — they stay in those config directories.

## Notes

- Free-text answers (prompts, paths) are pasted straight into the command line.
  Characters that are special to `cmd` (`&`, `|`, `>`, `^`) will misbehave — use
  **[E]** to fix the command by hand if you need them.
- **[F] Fix Environment** writes to your *user* `PATH` via
  `[Environment]::SetEnvironmentVariable`, deliberately not `setx` — `setx`
  truncates at 1024 characters and can silently destroy a long `PATH`.
- Flag names track the current CLIs; if a vendor renames one, edit the matching
  `set "CMD=..."` line.

## License

MIT — see [LICENSE](LICENSE).
