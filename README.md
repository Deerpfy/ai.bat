# ai.bat

A single-file Windows launcher for terminal AI coding agents. Run it in a project
folder, answer the menu prompts for whichever CLI you pick, check the assembled
command, and launch.

Supports Claude Code, Codex (OpenAI), Gemini (Google), Antigravity (`agy`),
DeepSeek, and any endpoint of your own. It's plain batch, so there is nothing to
install beyond the CLI itself.

```
  +----------------------------------------------------------------------+
  | AI LAUNCHER 2.4                           Select engine              |
  +----------------------------------------------------------------------+
   DIR   H:\Projects\myapp

  ENGINE
   [1] Claude                       Anthropic - full agentic CLI
   [2] Codex                        OpenAI - codex CLI, supports --yolo
   [3] Gemini                       Google - gemini CLI, supports --yolo
   [4] Antigravity                  Google - agy terminal agent
   [5] DeepSeek                     DeepSeek - their API, claude CLI
   [6] Custom API                   any endpoint, claude or codex CLI

  SETUP
   [F] Fix environment              set git-bash + PATH permanently
   [U] Update models                download the latest model lists
   [R] Right-click menu             OFF - not installed

  ------------------------------------------------------------------------
   KEYS  1-6   [F] env  [U] models  [R] right-click  [Q] quit  default 1
```

## Install

1. Put `ai.bat` where you want it: a tools folder, a submodule inside a project, or
   the repo you work in.
2. Double-click it, or run `ai` from a terminal.
3. Optional: pick [F] Fix Environment once. It stores `CLAUDE_CODE_GIT_BASH_PATH`
   and adds the folder holding `ai.bat` to your user `PATH`, so `ai` works from
   anywhere.
4. Optional: pick [R] Right-click menu, then [E], to put **AI Launcher** in the
   Windows right-click menu. See below.

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

## The Windows right-click menu

[R] on the engine menu is a global on/off switch for an **AI Launcher** entry in
Explorer's right-click menu. Turn it on and it appears on the desktop, on empty
space inside any folder, and on a folder itself; turn it off and it is gone. The
engine menu always shows which of the two it currently is, because the switch reads
the registry rather than trusting a saved flag - something else could have removed
the entry.

Clicking it opens the launcher with that folder as the working directory:

```
cmd.exe /s /c "pushd "%V" && "C:\tools\ai.bat" --dir "%V""
```

The `--dir` matters. On a normal start the launcher walks up from its own location
to find the project root, so without it a right-click in someone else's project
would still run the agent in the folder `ai.bat` lives in.

- Two per-user keys, `HKCU\Software\Classes\Directory\Background\shell\AILauncher`
  and `...\Directory\shell\AILauncher`. No admin rights, nothing machine-wide, and
  [D] deletes both.
- The icon is drawn on first install and cached in
  `%LOCALAPPDATA%\ai-launcher\ai-launcher.ico`, so the launcher stays a single file
  with nothing to ship next to it. Put your own `ai-launcher.ico` beside `ai.bat`,
  or point `AI_BAT_ICON` at any `.ico` or `"file.dll,index"` resource, to override
  it; an icon you supplied is never overwritten and never deleted. [D] removes only
  the cached one.
- Windows 11 lists third-party entries under **Show more options** (or Shift+F10).
  That is the shell's own rule for anything that is not a packaged extension.
- Without the menu: `ai.bat --context-menu on` and `ai.bat --context-menu off`.
- Moved `ai.bat` after installing? The [R] screen says so, and [E] re-points it.

## Requirements

- Windows with `cmd.exe` and PowerShell 5+ (preinstalled on Windows 10/11) -
  PowerShell reads `ai-models.json` and powers [F] fix env, [U] update models and
  [R] right-click menu
- At least one agent CLI on `PATH`: `claude`, `codex`, `gemini`, or `agy`
  (the DeepSeek and Custom API engines reuse `claude` or `codex` - see below)
- Git Bash if you use Claude Code. The script looks in the usual install locations
  (`%LOCALAPPDATA%\Programs\Git`, `Program Files`, scoop, or anything
  `where bash.exe` finds) and sets `CLAUDE_CODE_GIT_BASH_PATH` for you.

## What the Claude menu covers

Model, effort level, permission mode, session handling (new, continue, resume, fork,
from PR), verbose and debug output, extra working directories, system prompt (append
or replace), MCP config, tool restrictions, Chrome integration, git worktree with
optional tmux, startup mode (`--bare`, `--safe-mode`), and IDE attach. The DeepSeek
and Custom API engines reuse this same menu from the effort screen down.

Model option [C] queries `https://api.anthropic.com/v1/models` for the models your
account can use. It needs `ANTHROPIC_API_KEY` in your environment, or an `apiKey` in
`%APPDATA%\claude\config.json`. Without one it points you at `ai-models.json` instead.
The key is read at runtime and never stored by this script.

The last screen shows the full command and working directory before anything runs.
[E] lets you edit the command by hand, [D] changes the directory.

## Bring your own endpoint

`[5] DeepSeek` and `[6] Custom API` install nothing. Both point a CLI you already
have at a different endpoint:

| Endpoint speaks | CLI used | Model and effort travel as |
| --- | --- | --- |
| Anthropic Messages API | `claude` | `ANTHROPIC_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL` |
| OpenAI Responses API | `codex` | `-m` and `-c` provider overrides |

That is also why every screen after the endpoint questions - permissions,
sessions, MCP, tools, worktrees, approval and sandbox modes - is literally the
Claude or the Codex flow, not a trimmed-down copy of it.

### The key screen

Both engines share it:

- `[1]` paste a key and keep it for this run only
- `[2]` paste a key and also store it for your user, as `DEEPSEEK_API_KEY` or
  `AI_BAT_CUSTOM_KEY`, so later runs and new terminals skip the question
- `[3]` continue with the key already shown - one found in your environment is
  picked up automatically
- `[T]` spend one GET on the endpoint's model list and report what came back: a
  list, `401` (key rejected), `404` (reachable, but no model list at that path -
  normal for many gateways and no verdict on the key), or a connection error
- `[X]` delete the stored key again

Only the first and last few characters of a key are ever printed. Nothing is
written into the repo, and the key never reaches a command line - it is handed to
the agent through the environment, at launch, and dropped from the launcher's own
variables in the same breath.

Switching engines from the menu clears the endpoint, key and model, so one
endpoint's settings can never leak into another. A key you saved lives in the
environment and survives.

### DeepSeek

DeepSeek publishes an [Anthropic-compatible
endpoint](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code),
so `[5]` runs `claude` against `https://api.deepseek.com/anthropic` with the
variables from DeepSeek's own guide:

| Variable | Value |
| --- | --- |
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `ANTHROPIC_AUTH_TOKEN` | your key |
| `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL` | the model you picked, `deepseek-v4-pro` by default |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` | the fast model, `deepseek-v4-flash` by default |
| `CLAUDE_CODE_EFFORT_LEVEL` | the effort screen's answer, `max` by default |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `786432` |

Keys come from
[platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys). Point
`AI_BAT_DEEPSEEK_URL` elsewhere if you go through a gateway or a proxy.

### Custom API

`[6]` asks four things: which CLI drives it, the base URL, the key, and the model.

Give the base URL the provider documents - the CLI appends its own path.
`https://api.example.com/v1` for a Responses endpoint, `https://gw.example.com/anthropic`
for a Messages one. The CLI you pick decides which one is expected, and the hint
on the screen says which.

- **Claude Code** sets the same `ANTHROPIC_*` variables as the DeepSeek table
  above, minus the compaction window. A second screen pins the fast/subagent
  model, defaulting to your main model, because Claude Code would otherwise ask
  your endpoint for a Claude model name.
- **Codex** writes the provider onto the command line and never touches your
  `~/.codex/config.toml`:

  ```
  codex -c model_provider=aibat -c model_providers.aibat.name=aibat
        -c model_providers.aibat.base_url=<your URL>
        -c model_providers.aibat.env_key=AI_BAT_CUSTOM_KEY -m <your model>
  ```

  Codex reads the key out of `AI_BAT_CUSTOM_KEY` itself, so that is the only
  variable exported. Note that this codex accepts `wire_api = "responses"` and
  nothing else, so a gateway that only offers OpenAI *chat completions* will not
  work here - and neither will it under `claude`, which needs the Messages API.

Add your own entries under `"custom"` in `ai-models.json` and they become the
model menu; `--refresh-models` keeps that list untouched, since there is no
upstream to rebuild it from.

### Without the menu

`ai --ai deepseek` reads `DEEPSEEK_API_KEY`. `ai --ai custom` reads
`AI_BAT_CUSTOM_URL`, `AI_BAT_CUSTOM_KEY`, `AI_BAT_CUSTOM_MODEL` (or `--model`)
and `AI_BAT_CUSTOM_BACKEND` (`claude`, the default, or `codex`). Anything missing
is exit 5 rather than an agent that cannot authenticate - checked before
`--print-cmd` prints, so a half-written provider override never looks runnable.

Launching an Anthropic-shaped endpoint exports Anthropic variables into the
session it starts. Running `ai` again from inside that session would otherwise
inherit them and quietly send a *Claude* run to your endpoint, so the launcher
tags what it injected and drops exactly those names on the next start. Variables
you set yourself are left alone.

## The model lists

The Claude, Codex, DeepSeek and Custom API model menus come from `ai-models.json`,
which sits next to `ai.bat`. If the file is missing (say you copied `ai.bat` on
its own), it is recreated with defaults on first use.

```json
{
  "claude": [
    { "id": "claude-opus-5", "desc": "Opus 5 - newest Opus" }
  ],
  "codex": [
    { "id": "gpt-5.6-sol", "desc": "latest frontier agentic coding model" }
  ],
  "deepseek": [
    { "id": "deepseek-v4-pro", "desc": "V4 Pro - reasoning and agentic work" }
  ],
  "custom": [
    { "id": "my-gateway-model", "desc": "whatever your endpoint serves" }
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
- **DeepSeek** comes from [models.dev](https://models.dev/api.json), which
  carries names and release dates, falling back to the bare id list at
  `api.deepseek.com/models` when `DEEPSEEK_API_KEY` is set.
- **Custom** is never fetched - it is your list, and a rebuild carries it
  through unchanged.

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
else. Pick permission mode [4] manual, or [5] plan, if you want to be asked. DeepSeek
and a Claude-driven Custom API inherit the same default, since it is the same CLI.
The Codex and Gemini menus have equivalent `--yolo` options, marked `[DANGEROUS]`.

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
- The right-click icon is a multi-size `.ico` assembled by hand from PNG frames -
  an `ICONDIR`, one `ICONDIRENTRY` per size, then the payloads. Explorer has
  accepted PNG inside `.ico` since Vista. If drawing it fails for any reason the
  entry still installs, using the `cmd.exe` icon.
- Flag names follow the current CLIs. If a vendor renames one, edit the matching
  `set "CMD=..."` line.

## License

MIT. See [LICENSE](LICENSE).
