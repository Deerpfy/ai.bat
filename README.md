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

1. Put `ai.bat` where you want it: a tools folder, a submodule inside a project, or
   the repo you work in.
2. Double-click it, or run `ai` from a terminal.
3. Optional: pick [F] Fix Environment once. It stores `CLAUDE_CODE_GIT_BASH_PATH`
   and adds the folder holding `ai.bat` to your user `PATH`, so `ai` works from
   anywhere.

As a submodule:

```
git submodule add <url> tools/ai-launcher
```

## Working directory

The launcher is built to be vendored into a bigger project, as a git submodule or as
a plain copy. Opening it from that subfolder should still put the agent at the top of
the whole project, so on start it walks up from its own location and picks the
outermost directory that contains a `.git` entry.

```
myapp/                  <- agent runs here
  .git/
  src/
  tools/
    ai-launcher/        <- ai.bat lives here
      .git              (submodule pointer file)
      ai.bat
```

Nested submodules resolve the same way: the walk keeps going up and always lands on
the outermost repository. If there is no `.git` anywhere above it, the script falls
back to its own folder, which is what happens when you use it standalone.

Two ways to override:

- Set `AI_BAT_ROOT` to a directory before launching.
- Press `[D]` on the confirm screen to type a path, or `[S]` for the folder `ai.bat`
  lives in.

The resolved path is shown on the main menu and again on the confirm screen, so you
can see where the agent will run before it starts.

## Requirements

- Windows with `cmd.exe` and PowerShell 5+ (preinstalled on Windows 10/11) -
  PowerShell reads `ai-models.json` and powers [F] fix env and [U] update models
- At least one agent CLI on `PATH`: `claude`, `codex`, `gemini`, or `agy`
- Git Bash if you use Claude Code. The script looks in the usual install locations
  (`%LOCALAPPDATA%\Programs\Git`, `Program Files`, scoop, or anything
  `where bash.exe` finds) and sets `CLAUDE_CODE_GIT_BASH_PATH` for you.

## What the Claude menu covers

Model, effort level, permission mode, session handling (new, continue, resume, fork,
from PR), verbose and debug output, extra working directories, system prompt (append
or replace), MCP config, tool restrictions, Chrome integration, git worktree with
optional tmux, startup mode (`--bare`, `--safe-mode`), and IDE attach.

Model option [C] queries `https://api.anthropic.com/v1/models` for the models your
account can use. It needs `ANTHROPIC_API_KEY` in your environment, or an `apiKey` in
`%APPDATA%\claude\config.json`. Without one it points you at `ai-models.json` instead.
The key is read at runtime and never stored by this script.

The last screen shows the full command and working directory before anything runs.
[E] lets you edit the command by hand, [D] changes the directory.

## The model lists

The Claude and Codex model menus come from `ai-models.json`, which sits next to
`ai.bat`. If the file is missing (say you copied `ai.bat` on its own), it is
recreated with defaults on first use.

```json
{
  "claude": [
    { "id": "claude-opus-5", "desc": "Opus 5 - newest Opus" }
  ],
  "codex": [
    { "id": "gpt-5.6-sol", "desc": "latest frontier agentic coding model" }
  ]
}
```

Array order is menu order, and the first nine entries per engine become keys
[1]-[9]. Edit the file any time - the menus notice the change on their next
render, no restart needed. Reading the JSON costs one short PowerShell call per
change; the result is cached for the rest of the run, so navigating menus stays
instant. Characters outside a safe set (letters, digits, spaces and `. _ , + / @
: -`) are stripped from ids and descriptions, because both end up on a `cmd`
command line.

### Updating the lists from GitHub

`ai --update-models` (or [U] on the engine menu) downloads the current list from

```
https://raw.githubusercontent.com/Deerpfy/ai.bat/main/ai-models.json
```

validates that it parses as JSON, and only then replaces the local file. Push a
new `ai-models.json` to this repo and every copy can pull it on request - no
GitHub Pages setup needed, since raw.githubusercontent.com serves the file
directly. If you would rather host it elsewhere (a GitHub Pages site, any static
host), point `AI_BAT_MODELS_URL` at that URL; the mechanism is identical.

Set `AI_BAT_AUTO_UPDATE=1` to refresh automatically at launch, at most once a
day. Mind that a successful update replaces local hand edits to the file.

### Rebuilding from live sources

`ai --refresh-models` (or [L] on the update screen) rebuilds `ai-models.json`
from what is actually available right now, instead of hand-maintaining it:

- **Claude** comes from the official `api.anthropic.com/v1/models` when a key
  is found (`ANTHROPIC_API_KEY`, or `apiKey` in `%APPDATA%\claude\config.json`),
  falling back to [models.dev](https://models.dev/api.json) - a public,
  no-auth model database that uses the vendors' native ids, sorted here by
  release date.
- **Codex** comes from the picker cache codex itself maintains in
  `%USERPROFILE%\.codex\models_cache.json` (entries the picker lists, in its
  priority order). Those are the only slugs `codex -m` accepts, so the local
  cache beats any website.

A section whose sources are unreachable keeps its current entries; if nothing
is reachable the file is left untouched and the exit code is 1. The output is
deterministic, so re-running it with no upstream changes produces no diff.

The publishing loop for keeping every copy current: run `ai --refresh-models`,
review the result, push it to this repo - and every other copy picks it up via
[U] / `--update-models` / `AI_BAT_AUTO_UPDATE`.

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
