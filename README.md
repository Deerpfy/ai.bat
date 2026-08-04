# ai.bat

A single-file Windows launcher for terminal AI coding agents. Run it in a project
folder, answer the menu prompts for whichever CLI you pick, check the assembled
command, and launch.

Supports Claude Code, Codex (OpenAI), Gemini (Google) and Antigravity (`agy`).
It's plain batch, so there is nothing to install beyond the CLI itself.

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

1. Put `ai.bat` where you want it: a tools folder, or the repo you work in.
2. Double-click it, or run `ai` from a terminal.
3. Optional: pick [F] Fix Environment once. It stores `CLAUDE_CODE_GIT_BASH_PATH`
   and adds the script's folder to your user `PATH`, so `ai` works from anywhere.

The script `cd`s to its own folder on start, so the agent's working directory is
wherever `ai.bat` lives.

## Requirements

- Windows with `cmd.exe`
- At least one agent CLI on `PATH`: `claude`, `codex`, `gemini`, or `agy`
- Git Bash if you use Claude Code. The script looks in the usual install locations
  (`%LOCALAPPDATA%\Programs\Git`, `Program Files`, scoop, or anything
  `where bash.exe` finds) and sets `CLAUDE_CODE_GIT_BASH_PATH` for you.

## What the Claude menu covers

Model, effort level, permission mode, session handling (new, continue, resume, fork,
from PR), verbose and debug output, extra working directories, system prompt (append
or replace), MCP config, tool restrictions, Chrome integration, git worktree with
optional tmux, startup mode (`--bare`, `--safe-mode`), and IDE attach.

Model option [8] queries `https://api.anthropic.com/v1/models` for the models your
account can use. It needs `ANTHROPIC_API_KEY` in your environment, or an `apiKey` in
`%APPDATA%\claude\config.json`. Without one it prints a static list instead. The key
is read at runtime and never stored by this script.

The last screen shows the full command before anything runs. [E] lets you edit it by
hand.

## The default bypasses permission checks

Pressing Enter through every Claude prompt gives you
`claude --dangerously-skip-permissions`, which lets the agent run any command in that
folder without asking. That is fine for a repo you trust and a bad idea for anything
else. Pick permission mode [4] manual, or [5] plan, if you want to be asked. The
Codex and Gemini menus have equivalent `--yolo` options, marked `[DANGEROUS]`.

## Multiple Claude accounts

The account menu points `CLAUDE_CONFIG_DIR` at `%USERPROFILE%\.claude-acc1` or
`.claude-acc2`, so two logins can coexist without re-authenticating. Run [A] Auth
Setup once to log both in. The second login is easier in a different browser, since
the OAuth flow follows whichever browser is already signed in. Both accounts should
be your own; check your provider's terms before using this to get around usage
limits.

No credentials are stored in this repo. They stay in those config directories.

## Notes

- Free-text answers (prompts, paths) are pasted straight into the command line, so
  characters that are special to `cmd` (`&`, `|`, `>`, `^`) will misbehave. Use [E]
  to repair the command by hand if you need them.
- [F] Fix Environment writes to your user `PATH` with
  `[Environment]::SetEnvironmentVariable` rather than `setx`, because `setx`
  truncates at 1024 characters and can destroy a long `PATH` without warning.
- Flag names follow the current CLIs. If a vendor renames one, edit the matching
  `set "CMD=..."` line.

## License

MIT. See [LICENSE](LICENSE).
