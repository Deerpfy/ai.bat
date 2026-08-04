@echo off
rem ============================================================================
rem  AI LAUNCHER
rem  Picks an AI CLI (Claude / Codex / Gemini / Antigravity), then exposes that
rem  engine's own parameters, then shows the assembled command before running.
rem
rem  Encoding: ASCII / UTF-8 without BOM.  Line endings: CRLF.
rem  Exit codes: see :usage
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- identity --------------------------------------------------------------
set "BF_NAME=AI LAUNCHER"
set "BF_VERSION=2.2"

rem Captured here, at the top level, on purpose: inside a "call :label" the %0
rem token refers to the label, not to the script, so %~dp0 and %~nx0 are only
rem trustworthy before the first call.
set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "BF_SELF=%~nx0"

rem The editable model-menu list lives next to the script, not in the resolved
rem repo root, so a vendored copy keeps its own list. PowerShell converts the
rem JSON to pipe-delimited lines in MDL_LINES once per change (see :parse_models
rem and :load_models); the menus read only the lines file, so they stay instant.
set "MODELS_FILE=!SCRIPT_DIR!\ai-models.json"
set "MDL_LINES=%TEMP%\ai-bat-models-%RANDOM%%RANDOM%.lines"

rem Where --update-models and [U] download the list from. Point this at any URL
rem that serves the JSON: raw.githubusercontent.com needs no setup, a GitHub
rem Pages site works the same way.
if not defined AI_BAT_MODELS_URL set "AI_BAT_MODELS_URL=https://raw.githubusercontent.com/Deerpfy/ai.bat/main/ai-models.json"

rem ---- safety limits (BAT-201, BAT-202) --------------------------------------
set "BF_LOOP_CAP=400"
set "BF_IDLE_TIMEOUT=300"
set "BF_ROOT_CAP=64"
if defined AI_BAT_TIMEOUT set "BF_IDLE_TIMEOUT=%AI_BAT_TIMEOUT%"

rem ---- state -----------------------------------------------------------------
set "BF_EXIT=0"
set "BF_LOOPS=0"
set "BF_STOP="
set "BF_ASSUME_YES="
set "BF_PRINT_ONLY="
set "BF_FIXENV="
set "BF_EXTRA="
set "BF_CH="
set "AI_KIND="
set "AI_NAME="
set "AI_EDITED="
set "CMD="

rem setlocal copies the caller's environment, so any of these names already
rem present outside becomes a silently applied flag. That happens for real:
rem this launcher exports CMD, MODEL_FLAG and friends to the AI CLI it starts,
rem so a second ai.bat run from inside that session inherits them. Clear every
rem name the script owns before anything reads one.
for %%V in (
  MODEL_FLAG EFFORT_FLAG PERM_MODE CUSTOM_MODEL
  CL_SESSION CL_VERBOSE CL_ADDDIR CL_SYSPROMPT CL_MCP CL_TOOLS CL_CHROME
  CL_WORKTREE CL_STARTUP CL_IDE CL_SID CL_SNAME CL_PR CL_DBGCATS CL_DIRS
  CL_APPEND CL_REPLACE CL_MCPFILE CL_TOOLLIST CL_WTNAME
  CX_BASE CX_MODEL CX_APPR CX_SEARCH CX_CD CX_PROMPT CX_NEW CX_MODEL_ID
  CX_CD_DIR CX_PROMPT_TEXT
  GM_MODEL GM_APPR GM_SANDBOX GM_SESS GM_WT GM_DIRS GM_DEBUG GM_PROMPT
  GM_MODEL_ID GM_RIDX GM_WT_NAME GM_DIR_LIST GM_PFLAG GM_PROMPT_TEXT
  AG_SESS AG_PERM AG_SB AG_DIR AG_PROMPT AG_CONV AG_DIR_PATH AG_PFLAG
  AG_PROMPT_TEXT
  NEW_ROOT NEW_CMD SCAN PARENT AI_DIR PS_SCRIPT
  MDL_COUNT MDL_MORE MDL_STAMP MDL_BAD MDL_UPD_RC BF_MKEYS BF_MDEF BF_MRANGE
  BF_MST BF_UPDATE BF_REFRESH
) do set "%%V="

rem ---- accent: orange.  Override with AI_BAT_ACCENT (e.g. 33 for basic yellow)
set "BF_ACCENT=38;5;208"
set "BF_DIM=38;5;244"
if defined AI_BAT_ACCENT set "BF_ACCENT=%AI_BAT_ACCENT%"

rem ---- render constants, built rather than hand-counted ----------------------
set "BF_PAD=                    "
set "BF_PAD=!BF_PAD!!BF_PAD!!BF_PAD!!BF_PAD!"
set "BF_HR=----------"
set "BF_HR=!BF_HR!!BF_HR!!BF_HR!!BF_HR!!BF_HR!!BF_HR!!BF_HR!"
set "BF_RULE=!BF_HR!--"

call :detect_context
call :parse_args %*
if defined BF_STOP goto :cleanup
if not "!BF_EXIT!"=="0" goto :cleanup

call :resolve_root
call :detect_git_bash

if defined BF_FIXENV goto :env_fix_go
if defined BF_UPDATE goto :update_flag
if defined BF_REFRESH goto :refresh_flag

rem Opt-in launch-time refresh; fires at most once a day and is bounded by the
rem fetch timeout, so an offline machine stalls briefly once, not every start.
if defined AI_BAT_AUTO_UPDATE call :auto_update_check

rem Non-interactive callers (CI, scheduler, another script) never see the menu,
rem so the tool stays schedulable (BAT-010).
if defined BF_NONINTERACTIVE goto :headless
if defined AI_KIND goto :headless
goto :ai_select

:headless
if not defined AI_KIND goto :headless_noai
call :build
if defined BF_PRINT_ONLY goto :print_cmd
goto :run
:headless_noai
call :err "no interactive console available; pass --ai <claude|codex|gemini|antigravity> or --help"
set "BF_EXIT=2"
goto :cleanup
:print_cmd
echo(!CMD!
set "BF_EXIT=0"
goto :cleanup


rem ============================================================================
rem  TOP LEVEL: AI SELECTION
rem ============================================================================
:ai_select
set "AI_KIND="
set "AI_NAME="
set "AI_EDITED="
set "CMD="
call :header "Select engine"
call :sec "ENGINE"
call :item "1" "Claude"      "Anthropic - full agentic CLI"
call :item "2" "Codex"       "OpenAI - codex CLI, supports --yolo"
call :item "3" "Gemini"      "Google - gemini CLI, supports --yolo"
call :item "4" "Antigravity" "Google - agy terminal agent"
call :sec "SETUP"
call :item "F" "Fix environment" "set git-bash + PATH permanently"
call :item "U" "Update models"   "download the latest model lists"
call :foot "1 2 3 4   [F] fix env   [U] update   [Q] quit" "default 1"
call :menu_key "1234FUQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="F" goto :env_fix
if "!BF_CH!"=="U" goto :update_models
if "!BF_CH!"=="1" goto :claude_flow
if "!BF_CH!"=="2" goto :codex_flow
if "!BF_CH!"=="3" goto :gemini_flow
if "!BF_CH!"=="4" goto :antigravity_flow
goto :unreachable


rem ============================================================================
rem ============================================================================
rem  CLAUDE FLOW
rem ============================================================================
rem ============================================================================
:claude_flow
set "AI_KIND=claude"
set "AI_NAME=Claude"
set "CLAUDE_CONFIG_DIR="
set "MODEL_FLAG="
set "EFFORT_FLAG="
set "PERM_MODE="
set "CL_SESSION="
set "CL_VERBOSE="
set "CL_ADDDIR="
set "CL_SYSPROMPT="
set "CL_MCP="
set "CL_TOOLS="
set "CL_CHROME="
set "CL_WORKTREE="
set "CL_STARTUP="
set "CL_IDE="

rem --- 0. ACCOUNT -------------------------------------------------------------
:cl_account
call :header "Claude / Account"
if not defined CLAUDE_CODE_GIT_BASH_PATH call :warn "Git Bash not found - Claude needs it on Windows. Install from https://git-scm.com/downloads/win or run [F] from the engine menu."
call :sec "ACCOUNT"
call :item "1" "Account 1"  "primary profile,  .claude-acc1"
call :item "2" "Account 2"  "fallback profile, .claude-acc2"
call :item "3" "Default"    "no account switch"
call :item "A" "Auth setup" "first-time login for both accounts"
call :foot "1 2 3   [A] auth   [B] back   [Q] quit" "default 1"
call :menu_key "123ABQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ai_select
if "!BF_CH!"=="A" goto :auth_setup
if "!BF_CH!"=="1" set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc1"
if "!BF_CH!"=="2" set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc2"

rem --- 1. MODEL ---------------------------------------------------------------
rem Menu entries come from ai-models.json (engine tag "claude") and are reread
rem on every render, so an edit to the file shows up immediately.
:cl_model
call :header "Claude / Model"
call :load_models claude
call :sec "MODEL"
for /l %%i in (1,1,!MDL_COUNT!) do call :item "%%i" "!MDL_%%i!" "!MDD_%%i!"
call :item "C" "Custom model ID" "lists models available on your key"
call :item "S" "Skip"            "no --model flag"
call :note "Edit ai-models.json next to !BF_SELF! to change this list."
if defined MDL_BAD call :note "ai-models.json has a JSON error - fix it or re-download via [U]."
if defined MDL_MORE call :note "Only the first 9 claude entries in ai-models.json are shown."
if "!MDL_COUNT!"=="0" call :note "No claude entries in ai-models.json - pick [C] or [S]."
set "BF_MKEYS="
for /l %%i in (1,1,!MDL_COUNT!) do set "BF_MKEYS=!BF_MKEYS!%%i"
set "BF_MDEF=1"
if "!MDL_COUNT!"=="0" set "BF_MDEF=C"
set "BF_MRANGE=1-!MDL_COUNT!   "
if "!MDL_COUNT!"=="1" set "BF_MRANGE=1   "
if "!MDL_COUNT!"=="0" set "BF_MRANGE="
call :foot "!BF_MRANGE![C] custom   [S] skip   [B] back   [Q] quit" "default !BF_MDEF!"
call :menu_key "!BF_MKEYS!CSBQ" "!BF_MDEF!"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_account
set "MODEL_FLAG="
if "!BF_CH!"=="C" goto :cl_custom_model
if "!BF_CH!"=="S" goto :cl_effort
for %%i in (!BF_CH!) do set "MODEL_FLAG=--model !MDL_%%i!"
goto :cl_effort

:cl_custom_model
call :header "Claude / Model / Custom"
call :sec "AVAILABLE MODELS"
echo(
call :fetch_models
echo(
call :note "Tip: /model inside Claude switches models mid-session."
call :note "Blank entry keeps the previous choice."
echo(
call :ask CUSTOM_MODEL "Model ID: "
if defined CUSTOM_MODEL set "MODEL_FLAG=--model !CUSTOM_MODEL!"

rem --- 2. EFFORT --------------------------------------------------------------
:cl_effort
call :header "Claude / Effort"
call :sec "EFFORT LEVEL"
call :item "1" "Default"    "no --effort flag"
call :item "2" "Low"        "fast, light reasoning"
call :item "3" "Medium"     "standard tasks"
call :item "4" "High"       "complex tasks"
call :item "5" "Extra high" "deep analysis"
call :item "6" "Maximum"    "hardest problems"
call :foot "1-6   [B] back   [Q] quit" "default 1"
call :menu_key "123456BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_model
set "EFFORT_FLAG="
if "!BF_CH!"=="2" set "EFFORT_FLAG=--effort low"
if "!BF_CH!"=="3" set "EFFORT_FLAG=--effort medium"
if "!BF_CH!"=="4" set "EFFORT_FLAG=--effort high"
if "!BF_CH!"=="5" set "EFFORT_FLAG=--effort xhigh"
if "!BF_CH!"=="6" set "EFFORT_FLAG=--effort max"

rem --- 3. PERMISSION MODE -----------------------------------------------------
:cl_perm
call :header "Claude / Permissions"
call :sec "PERMISSION MODE"
call :item "1" "bypassPermissions" "--dangerously-skip-permissions"
call :item "2" "dontAsk"           "auto-approve, no prompts"
call :item "3" "acceptEdits"       "auto edits, prompt for commands"
call :item "4" "manual"            "prompt for sensitive actions"
call :item "5" "plan"              "show plan first, then execute"
call :item "6" "auto"              "auto-approve safe, ask on risky"
call :foot "1-6   [B] back   [Q] quit" "default 1"
call :menu_key "123456BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_effort
set "PERM_MODE="
if "!BF_CH!"=="2" set "PERM_MODE=dontAsk"
if "!BF_CH!"=="3" set "PERM_MODE=acceptEdits"
if "!BF_CH!"=="4" set "PERM_MODE=manual"
if "!BF_CH!"=="5" set "PERM_MODE=plan"
if "!BF_CH!"=="6" set "PERM_MODE=auto"

rem --- 4. SESSION -------------------------------------------------------------
:cl_session
call :header "Claude / Session"
call :sec "SESSION"
call :item "1" "New session"          "default"
call :item "2" "Continue last"        "-c"
call :item "3" "Resume specific"      "-r <id|name>"
call :item "4" "New, custom name"     "-n <name>"
call :item "5" "Continue as fork"     "-c --fork-session, new id"
call :item "6" "Resume from PR"       "--from-pr, blank = picker"
call :foot "1-6   [B] back   [Q] quit" "default 1"
call :menu_key "123456BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_perm
set "CL_SESSION="
if "!BF_CH!"=="2" set "CL_SESSION= -c"
if "!BF_CH!"=="5" set "CL_SESSION= -c --fork-session"
if "!BF_CH!"=="3" goto :cl_session_resume
if "!BF_CH!"=="4" goto :cl_session_name
if "!BF_CH!"=="6" goto :cl_session_pr
goto :cl_verbose
:cl_session_resume
call :ask CL_SID "Session ID or name: "
if defined CL_SID set "CL_SESSION= -r !CL_SID!"
goto :cl_verbose
:cl_session_name
call :ask CL_SNAME "Session name: "
if defined CL_SNAME set "CL_SESSION= -n !CL_SNAME!"
goto :cl_verbose
:cl_session_pr
call :ask CL_PR "PR number or URL (blank = picker): "
set "CL_SESSION= --from-pr"
if defined CL_PR set "CL_SESSION= --from-pr !CL_PR!"

rem --- 5. VERBOSE / DEBUG -----------------------------------------------------
:cl_verbose
call :header "Claude / Logging"
call :sec "VERBOSE / DEBUG"
call :item "1" "Normal"        "default"
call :item "2" "Verbose"       "--verbose"
call :item "3" "Debug"         "--debug"
call :item "4" "Debug + filter" "--debug <categories>"
call :foot "1-4   [B] back   [Q] quit" "default 1"
call :menu_key "1234BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_session
set "CL_VERBOSE="
if "!BF_CH!"=="2" set "CL_VERBOSE= --verbose"
if "!BF_CH!"=="3" set "CL_VERBOSE= --debug"
if "!BF_CH!"=="4" goto :cl_verbose_cats
goto :cl_adddir
:cl_verbose_cats
call :ask CL_DBGCATS "Debug categories (comma-separated): "
set "CL_VERBOSE= --debug"
if defined CL_DBGCATS set "CL_VERBOSE= --debug !CL_DBGCATS!"

rem --- 6. ADDITIONAL DIRECTORIES ----------------------------------------------
:cl_adddir
call :header "Claude / Directories"
call :sec "ADDITIONAL WORKING DIRECTORIES"
call :item "1" "None"           "default"
call :item "2" "Add directories" "--add-dir"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_verbose
set "CL_ADDDIR="
if not "!BF_CH!"=="2" goto :cl_sysprompt
call :ask CL_DIRS "Directory paths (space-separated): "
if defined CL_DIRS set "CL_ADDDIR= --add-dir !CL_DIRS!"

rem --- 7. SYSTEM PROMPT -------------------------------------------------------
:cl_sysprompt
call :header "Claude / System prompt"
call :sec "SYSTEM PROMPT"
call :item "1" "Default"          "use CLAUDE.md"
call :item "2" "Append text"      "--append-system-prompt"
call :item "3" "Replace entirely" "--system-prompt"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_adddir
set "CL_SYSPROMPT="
if "!BF_CH!"=="2" goto :cl_sysprompt_append
if "!BF_CH!"=="3" goto :cl_sysprompt_replace
goto :cl_mcp
:cl_sysprompt_append
call :opnote
call :ask CL_APPEND "Text to append: "
if defined CL_APPEND set "CL_SYSPROMPT= --append-system-prompt "!CL_APPEND!""
goto :cl_mcp
:cl_sysprompt_replace
call :opnote
call :ask CL_REPLACE "Replacement system prompt: "
if defined CL_REPLACE set "CL_SYSPROMPT= --system-prompt "!CL_REPLACE!""

rem --- 8. MCP -----------------------------------------------------------------
:cl_mcp
call :header "Claude / MCP"
call :sec "MCP SERVER CONFIG"
call :item "1" "None"            "default"
call :item "2" "Load config"     "--mcp-config <file>"
call :item "3" "Strict MCP only" "--strict-mcp-config --mcp-config"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_sysprompt
set "CL_MCP="
if "!BF_CH!"=="1" goto :cl_tools
call :ask CL_MCPFILE "MCP config file path: "
if not defined CL_MCPFILE goto :cl_tools
if "!BF_CH!"=="2" set "CL_MCP= --mcp-config !CL_MCPFILE!"
if "!BF_CH!"=="3" set "CL_MCP= --strict-mcp-config --mcp-config !CL_MCPFILE!"

rem --- 9. TOOL RESTRICTIONS ---------------------------------------------------
:cl_tools
call :header "Claude / Tools"
call :sec "TOOL RESTRICTIONS"
call :item "1" "All tools"      "default"
call :item "2" "Specific only"  "--tools <list>"
call :item "3" "No tools"       "--tools with an empty list"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_mcp
set "CL_TOOLS="
if "!BF_CH!"=="3" set "CL_TOOLS= --tools """
if not "!BF_CH!"=="2" goto :cl_chrome
call :note "Bash Edit Read Write Glob Grep WebFetch WebSearch Task NotebookEdit"
echo(
call :ask CL_TOOLLIST "Tool names (comma-separated): "
if defined CL_TOOLLIST set "CL_TOOLS= --tools "!CL_TOOLLIST!""

rem --- 10. CHROME -------------------------------------------------------------
:cl_chrome
call :header "Claude / Browser"
call :sec "CHROME INTEGRATION"
call :item "1" "Default" "no flag"
call :item "2" "Enable"  "--chrome"
call :item "3" "Disable" "--no-chrome"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_tools
set "CL_CHROME="
if "!BF_CH!"=="2" set "CL_CHROME= --chrome"
if "!BF_CH!"=="3" set "CL_CHROME= --no-chrome"

rem --- 11. GIT WORKTREE -------------------------------------------------------
:cl_worktree
call :header "Claude / Worktree"
call :sec "GIT WORKTREE"
call :item "1" "None"            "work in this checkout"
call :item "2" "New worktree"    "-w, isolated repo copy"
call :item "3" "Worktree + tmux" "-w --tmux, needs tmux"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_chrome
set "CL_WORKTREE="
if "!BF_CH!"=="1" goto :cl_startup
call :ask CL_WTNAME "Worktree name (blank = auto): "
set "CL_WORKTREE= -w"
if defined CL_WTNAME set "CL_WORKTREE= -w !CL_WTNAME!"
if "!BF_CH!"=="3" set "CL_WORKTREE=!CL_WORKTREE! --tmux"

rem --- 12. STARTUP MODE -------------------------------------------------------
:cl_startup
call :header "Claude / Startup"
call :sec "STARTUP MODE"
call :item "1" "Normal"    "hooks, plugins, CLAUDE.md as usual"
call :item "2" "Bare"      "--bare, fastest start"
call :item "3" "Safe mode" "--safe-mode, all customizations off"
call :note "Bare skips hooks/plugins/CLAUDE.md and needs ANTHROPIC_API_KEY."
call :note "Account OAuth will NOT work under --bare."
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_worktree
set "CL_STARTUP="
if "!BF_CH!"=="2" set "CL_STARTUP= --bare"
if "!BF_CH!"=="3" set "CL_STARTUP= --safe-mode"

rem --- 13. IDE ----------------------------------------------------------------
:cl_ide
call :header "Claude / IDE"
call :sec "IDE INTEGRATION"
call :item "1" "None"         "default"
call :item "2" "Auto-connect" "--ide, VS Code / JetBrains"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cl_startup
set "CL_IDE="
if "!BF_CH!"=="2" set "CL_IDE= --ide"
goto :confirm


rem ============================================================================
rem ============================================================================
rem  CODEX FLOW (OpenAI)
rem ============================================================================
rem ============================================================================
:codex_flow
set "AI_KIND=codex"
set "AI_NAME=Codex"
set "CLAUDE_CONFIG_DIR="
set "CX_BASE=codex"
set "CX_MODEL="
set "CX_APPR="
set "CX_SEARCH="
set "CX_CD="
set "CX_PROMPT="

:cx_session
call :header "Codex / Session"
call :sec "SESSION"
call :item "1" "New session"  "default"
call :item "2" "Resume"       "codex resume, picker"
call :item "3" "Resume last"  "codex resume --last"
call :item "4" "Fork"         "codex fork, picker"
call :item "5" "Fork last"    "codex fork --last"
call :foot "1-5   [B] back   [Q] quit" "default 1"
call :menu_key "12345BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ai_select
set "CX_BASE=codex"
if "!BF_CH!"=="2" set "CX_BASE=codex resume"
if "!BF_CH!"=="3" set "CX_BASE=codex resume --last"
if "!BF_CH!"=="4" set "CX_BASE=codex fork"
if "!BF_CH!"=="5" set "CX_BASE=codex fork --last"
set "CX_NEW=!BF_CH!"

rem Menu entries come from ai-models.json (engine tag "codex") and are reread on
rem every render. Refresh that file from the picker list codex itself caches in
rem ~/.codex/models_cache.json (visibility "list") when it ages.
:cx_model
call :header "Codex / Model"
call :load_models codex
call :sec "MODEL"
for /l %%i in (1,1,!MDL_COUNT!) do call :item "%%i" "!MDL_%%i!" "!MDD_%%i!"
call :item "C" "Custom model id" "-m <id>"
call :item "S" "Default"         "no -m flag, uses ~/.codex/config.toml"
call :note "Edit ai-models.json next to !BF_SELF! to change this list."
if defined MDL_BAD call :note "ai-models.json has a JSON error - fix it or re-download via [U]."
if defined MDL_MORE call :note "Only the first 9 codex entries in ai-models.json are shown."
if "!MDL_COUNT!"=="0" call :note "No codex entries in ai-models.json - pick [C] or [S]."
set "BF_MKEYS="
for /l %%i in (1,1,!MDL_COUNT!) do set "BF_MKEYS=!BF_MKEYS!%%i"
set "BF_MRANGE=1-!MDL_COUNT!   "
if "!MDL_COUNT!"=="1" set "BF_MRANGE=1   "
if "!MDL_COUNT!"=="0" set "BF_MRANGE="
call :foot "!BF_MRANGE![C] custom   [S] default   [B] back   [Q] quit" "default S"
call :menu_key "!BF_MKEYS!CSBQ" "S"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cx_session
set "CX_MODEL="
if "!BF_CH!"=="S" goto :cx_appr
if "!BF_CH!"=="C" goto :cx_custom_model
for %%i in (!BF_CH!) do set "CX_MODEL= -m !MDL_%%i!"
goto :cx_appr
:cx_custom_model
call :note "The menu list lives in ai-models.json next to !BF_SELF!."
echo(
call :ask CX_MODEL_ID "Model id: "
if defined CX_MODEL_ID set "CX_MODEL= -m !CX_MODEL_ID!"

:cx_appr
call :header "Codex / Approval"
call :sec "APPROVAL AND SANDBOX"
call :item "1" "Default"          "codex built-in policy"
call :item "2" "YOLO"             "--yolo, no approvals, no sandbox"
call :item "3" "Full access"      "-s danger-full-access -a never"
call :item "4" "Workspace-write"  "-s workspace-write -a on-request"
call :item "5" "Read-only"        "-s read-only -a untrusted"
call :note "[2] and [3] remove every guardrail. Nothing will ask first."
call :foot "1-5   [B] back   [Q] quit" "default 1"
call :menu_key "12345BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cx_model
set "CX_APPR="
if "!BF_CH!"=="2" set "CX_APPR= --yolo"
if "!BF_CH!"=="3" set "CX_APPR= -s danger-full-access -a never"
if "!BF_CH!"=="4" set "CX_APPR= -s workspace-write -a on-request"
if "!BF_CH!"=="5" set "CX_APPR= -s read-only -a untrusted"

:cx_search
call :header "Codex / Web search"
call :sec "WEB SEARCH"
call :item "1" "Off" "default"
call :item "2" "On"  "--search"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cx_appr
set "CX_SEARCH="
if "!BF_CH!"=="2" set "CX_SEARCH= --search"

:cx_cd
call :header "Codex / Working directory"
call :sec "WORKING DIRECTORY"
call :item "1" "This folder"  "default"
call :item "2" "Custom root"  "-C <path>"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cx_search
set "CX_CD="
if not "!BF_CH!"=="2" goto :cx_prompt
call :ask CX_CD_DIR "Directory path: "
if defined CX_CD_DIR set "CX_CD= -C "!CX_CD_DIR!""

:cx_prompt
set "CX_PROMPT="
if not "!CX_NEW!"=="1" goto :confirm
call :header "Codex / Initial prompt"
call :sec "INITIAL PROMPT"
call :item "1" "None"   "start interactive"
call :item "2" "Provide a prompt" "passed as the first turn"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cx_cd
if not "!BF_CH!"=="2" goto :confirm
call :opnote
call :ask CX_PROMPT_TEXT "Prompt: "
if defined CX_PROMPT_TEXT set "CX_PROMPT= "!CX_PROMPT_TEXT!""
goto :confirm


rem ============================================================================
rem ============================================================================
rem  GEMINI FLOW (Google)
rem ============================================================================
rem ============================================================================
:gemini_flow
set "AI_KIND=gemini"
set "AI_NAME=Gemini"
set "CLAUDE_CONFIG_DIR="
set "GM_MODEL="
set "GM_APPR="
set "GM_SANDBOX="
set "GM_SESS="
set "GM_WT="
set "GM_DIRS="
set "GM_DEBUG="
set "GM_PROMPT="

:gm_model
call :header "Gemini / Model"
call :sec "MODEL"
call :item "1" "Default"         "from config"
call :item "2" "Custom model id" "-m <id>"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ai_select
set "GM_MODEL="
if not "!BF_CH!"=="2" goto :gm_appr
call :note "e.g. gemini-2.5-pro, gemini-2.5-flash"
echo(
call :ask GM_MODEL_ID "Model id: "
if defined GM_MODEL_ID set "GM_MODEL= -m !GM_MODEL_ID!"

:gm_appr
call :header "Gemini / Approval"
call :sec "APPROVAL MODE"
call :item "1" "Default"   "prompt for approval"
call :item "2" "YOLO"      "--yolo, auto-accept everything"
call :item "3" "Auto-edit" "--approval-mode auto_edit"
call :item "4" "Plan"      "--approval-mode plan, read-only"
call :note "[2] accepts every action without asking."
call :foot "1-4   [B] back   [Q] quit" "default 1"
call :menu_key "1234BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_model
set "GM_APPR="
if "!BF_CH!"=="2" set "GM_APPR= --yolo"
if "!BF_CH!"=="3" set "GM_APPR= --approval-mode auto_edit"
if "!BF_CH!"=="4" set "GM_APPR= --approval-mode plan"

:gm_sandbox
call :header "Gemini / Sandbox"
call :sec "SANDBOX"
call :item "1" "Off" "default"
call :item "2" "On"  "--sandbox"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_appr
set "GM_SANDBOX="
if "!BF_CH!"=="2" set "GM_SANDBOX= --sandbox"

:gm_session
call :header "Gemini / Session"
call :sec "SESSION"
call :item "1" "New session"     "default"
call :item "2" "Resume latest"   "--resume latest"
call :item "3" "Resume by index" "--resume <n>"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_sandbox
set "GM_SESS="
if "!BF_CH!"=="2" set "GM_SESS= --resume latest"
if not "!BF_CH!"=="3" goto :gm_worktree
call :ask GM_RIDX "Session index number: "
if defined GM_RIDX set "GM_SESS= --resume !GM_RIDX!"

:gm_worktree
call :header "Gemini / Worktree"
call :sec "GIT WORKTREE"
call :item "1" "None"         "default"
call :item "2" "New worktree" "-w, blank name = auto"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_session
set "GM_WT="
if not "!BF_CH!"=="2" goto :gm_dirs
call :ask GM_WT_NAME "Worktree name (blank = auto): "
set "GM_WT= -w"
if defined GM_WT_NAME set "GM_WT= -w !GM_WT_NAME!"

:gm_dirs
call :header "Gemini / Directories"
call :sec "ADDITIONAL WORKING DIRECTORIES"
call :item "1" "None"              "default"
call :item "2" "Include dirs"      "--include-directories"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_worktree
set "GM_DIRS="
if not "!BF_CH!"=="2" goto :gm_debug
call :ask GM_DIR_LIST "Directories (comma-separated): "
if defined GM_DIR_LIST set "GM_DIRS= --include-directories !GM_DIR_LIST!"

:gm_debug
call :header "Gemini / Logging"
call :sec "DEBUG"
call :item "1" "Off" "default"
call :item "2" "On"  "--debug"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_dirs
set "GM_DEBUG="
if "!BF_CH!"=="2" set "GM_DEBUG= --debug"

:gm_prompt
call :header "Gemini / Initial prompt"
call :sec "INITIAL PROMPT"
call :item "1" "None"        "start interactive"
call :item "2" "Interactive" "-i <prompt>"
call :item "3" "Headless"    "-p <prompt>, non-interactive"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :gm_debug
set "GM_PROMPT="
if "!BF_CH!"=="1" goto :confirm
set "GM_PFLAG=-i"
if "!BF_CH!"=="3" set "GM_PFLAG=-p"
call :opnote
call :ask GM_PROMPT_TEXT "Prompt: "
if defined GM_PROMPT_TEXT set "GM_PROMPT= !GM_PFLAG! "!GM_PROMPT_TEXT!""
goto :confirm


rem ============================================================================
rem ============================================================================
rem  ANTIGRAVITY FLOW (Google - agy terminal agent)
rem ============================================================================
rem ============================================================================
:antigravity_flow
set "AI_KIND=agy"
set "AI_NAME=Antigravity"
set "CLAUDE_CONFIG_DIR="
set "AG_SESS="
set "AG_PERM="
set "AG_SB="
set "AG_DIR="
set "AG_PROMPT="

:ag_session
call :header "Antigravity / Session"
call :sec "SESSION"
call :item "1" "New conversation"     "default"
call :item "2" "Continue most recent" "-c"
call :item "3" "Resume by id"         "--conversation <id>"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ai_select
set "AG_SESS="
if "!BF_CH!"=="2" set "AG_SESS= -c"
if not "!BF_CH!"=="3" goto :ag_perm
call :ask AG_CONV "Conversation ID: "
if defined AG_CONV set "AG_SESS= --conversation !AG_CONV!"

:ag_perm
call :header "Antigravity / Permissions"
call :sec "PERMISSIONS"
call :item "1" "Default" "prompt for each tool action"
call :item "2" "YOLO"    "--dangerously-skip-permissions"
call :note "[2] auto-approves every tool permission."
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ag_session
set "AG_PERM="
if "!BF_CH!"=="2" set "AG_PERM= --dangerously-skip-permissions"

:ag_sandbox
call :header "Antigravity / Sandbox"
call :sec "SANDBOX"
call :item "1" "Off" "default"
call :item "2" "On"  "--sandbox, terminal restrictions"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ag_perm
set "AG_SB="
if "!BF_CH!"=="2" set "AG_SB= --sandbox"

:ag_dirs
call :header "Antigravity / Directories"
call :sec "ADDITIONAL WORKING DIRECTORIES"
call :item "1" "None"          "default"
call :item "2" "Add directory" "--add-dir <path>"
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ag_sandbox
set "AG_DIR="
if not "!BF_CH!"=="2" goto :ag_prompt
call :ask AG_DIR_PATH "Directory path: "
if defined AG_DIR_PATH set "AG_DIR= --add-dir "!AG_DIR_PATH!""

:ag_prompt
call :header "Antigravity / Initial prompt"
call :sec "INITIAL PROMPT"
call :item "1" "None"        "start interactive"
call :item "2" "Interactive" "-i <prompt>"
call :item "3" "Headless"    "-p <prompt>, print once"
call :foot "1 2 3   [B] back   [Q] quit" "default 1"
call :menu_key "123BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ag_dirs
set "AG_PROMPT="
if "!BF_CH!"=="1" goto :confirm
set "AG_PFLAG=-i"
if "!BF_CH!"=="3" set "AG_PFLAG=-p"
call :opnote
call :ask AG_PROMPT_TEXT "Prompt: "
if defined AG_PROMPT_TEXT set "AG_PROMPT= !AG_PFLAG! "!AG_PROMPT_TEXT!""
goto :confirm


rem ============================================================================
rem  COMMAND BUILDERS
rem  Every flow stores its choices in named variables and rebuilds CMD from
rem  scratch on each render, so [B] back never double-appends a flag.
rem ============================================================================
:build
rem A hand-edited command is authoritative; never regenerate over the top of it.
if defined AI_EDITED goto :eof
if "!AI_KIND!"=="claude" goto :build_claude
if "!AI_KIND!"=="codex"  goto :build_codex
if "!AI_KIND!"=="gemini" goto :build_gemini
if "!AI_KIND!"=="agy"    goto :build_agy
goto :eof

:build_claude
set "CMD=claude --dangerously-skip-permissions"
if defined PERM_MODE set "CMD=claude --permission-mode !PERM_MODE!"
if defined MODEL_FLAG set "CMD=!CMD! !MODEL_FLAG!"
if defined EFFORT_FLAG set "CMD=!CMD! !EFFORT_FLAG!"
set "CMD=!CMD!!CL_SESSION!!CL_VERBOSE!!CL_ADDDIR!!CL_SYSPROMPT!!CL_MCP!"
set "CMD=!CMD!!CL_TOOLS!!CL_CHROME!!CL_WORKTREE!!CL_STARTUP!!CL_IDE!!BF_EXTRA!"
goto :eof

:build_codex
set "CMD=!CX_BASE!!CX_MODEL!!CX_APPR!!CX_SEARCH!!CX_CD!!BF_EXTRA!!CX_PROMPT!"
goto :eof

:build_gemini
set "CMD=gemini!GM_MODEL!!GM_APPR!!GM_SANDBOX!!GM_SESS!!GM_WT!!GM_DIRS!!GM_DEBUG!!BF_EXTRA!!GM_PROMPT!"
goto :eof

:build_agy
set "CMD=agy!AG_SESS!!AG_PERM!!AG_SB!!AG_DIR!!BF_EXTRA!!AG_PROMPT!"
goto :eof


rem ============================================================================
rem  SHARED: CONFIRM / EDIT / CHDIR / RUN
rem ============================================================================
:confirm
call :header "Confirm"
call :sec "READY"
call :item "Y" "Launch"       "run the command above"
call :item "E" "Edit command" "hand-edit before running"
call :item "D" "Change dir"   "pick a different working directory"
call :item "R" "Engine menu"  "start over"
call :foot "[Y] launch  [E] edit  [D] dir  [R] restart  [Q] quit" "timeout quits"
call :menu_key "YEDRQ" "Q"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="Y" goto :run
if "!BF_CH!"=="E" goto :edit
if "!BF_CH!"=="D" goto :chdir
if "!BF_CH!"=="R" goto :ai_select
goto :unreachable

:chdir
call :header "Working directory"
call :sec "CURRENT"
call :kv "Working" "!REPO_ROOT!"
call :kv "Script " "!SCRIPT_DIR!"
call :sec "NEW"
call :note "Enter a path, S for the script folder, or blank to keep the current one."
echo(
call :ask NEW_ROOT "Working directory: "
if not defined NEW_ROOT goto :confirm
if /i "!NEW_ROOT!"=="S" set "NEW_ROOT=!SCRIPT_DIR!"
if not exist "!NEW_ROOT!\." goto :chdir_bad
set "REPO_ROOT=!NEW_ROOT!"
goto :confirm
:chdir_bad
call :err "not a directory: !NEW_ROOT! - check the path and try again"
call :hold
goto :confirm

:edit
call :header "Edit command"
call :sec "CURRENT COMMAND"
echo(
echo(   !CMD!
echo(
call :note "Blank entry keeps the command unchanged."
echo(
call :ask NEW_CMD "Command: "
rem Only a real edit freezes the command; a blank entry leaves the flow's own
rem rebuild in charge.
if defined NEW_CMD set "CMD=!NEW_CMD!"
if defined NEW_CMD set "AI_EDITED=1"
call :header "Edit command"
call :sec "UPDATED"
call :foot "[Y] launch   [N] back" "timeout = back"
call :menu_key "YN" "N"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Y" goto :run
goto :confirm

:run
if not defined BF_NONINTERACTIVE call :header "Launching"
if not defined CMD goto :run_nocmd
call :info "Starting !AI_NAME! in !REPO_ROOT!"
echo(
pushd "!REPO_ROOT!" 2>nul || goto :run_baddir
rem Percent expansion on purpose: it is the only form that runs a command
rem containing shell operators. See :check_operators for the tradeoff.
call %CMD%
set "BF_EXIT=!ERRORLEVEL!"
popd
echo(
call :info "!AI_NAME! session ended with exit code !BF_EXIT!"
goto :cleanup
:run_nocmd
call :err "no command was built; pick an engine first"
set "BF_EXIT=2"
goto :cleanup
:run_baddir
call :err "cannot enter working directory !REPO_ROOT! - it may have been deleted or renamed"
set "BF_EXIT=5"
goto :cleanup


rem ============================================================================
rem  AUTH SETUP (Claude - first-time login for both accounts)
rem ============================================================================
:auth_setup
call :header "Claude / Auth setup"
call :sec "ACCOUNT AUTH"
call :note "Logs in two accounts. Run once. After this, pick [1] or [2]."
call :rule

call :sec "ACCOUNT 1 - LOG IN VIA CHROME"
call :note "Make sure Account 1 is logged in on claude.ai in Chrome."
call :note "A browser will open for OAuth."
call :foot "[Y] continue   [S] skip   [Q] quit" "timeout skips"
call :menu_key "YSQ" "S"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="S" goto :auth_acc2
echo(
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc1"
claude auth login
echo(
call :sec "ACCOUNT 1 STATUS"
claude auth status

:auth_acc2
call :header "Claude / Auth setup"
call :sec "ACCOUNT 2 - LOG IN VIA BRAVE"
call :note "Make sure Account 2 is logged in on claude.ai in Brave."
call :note "If Chrome opens instead, copy the URL into Brave."
call :foot "[Y] continue   [S] skip   [Q] quit" "timeout skips"
call :menu_key "YSQ" "S"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="S" goto :auth_done
echo(
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc2"
claude auth login
echo(
call :sec "ACCOUNT 2 STATUS"
claude auth status

:auth_done
echo(
call :ok "Auth setup finished. Returning to the account menu."
set "CLAUDE_CONFIG_DIR="
call :hold
goto :cl_account


rem ============================================================================
rem  ENV FIX (set git-bash + PATH permanently)
rem  setx is deliberately not used: it truncates at 1024 chars and can wreck PATH.
rem ============================================================================
:env_fix
call :header "Fix environment"
call :sec "WHAT THIS CHANGES"
call :note "1. Sets CLAUDE_CODE_GIT_BASH_PATH in your user environment."
call :note "2. Appends this script's folder to your user PATH."
echo(
call :kv "Bash  " "!CLAUDE_CODE_GIT_BASH_PATH!"
call :kv "Folder" "!SCRIPT_DIR!"
if defined BF_ASSUME_YES goto :env_fix_go
call :foot "[Y] apply   [N] cancel" "timeout = no"
call :menu_key "YN" "N"
if defined BF_STOP goto :cleanup
if not "!BF_CH!"=="Y" goto :env_fix_cancel

:env_fix_go
echo(
call :sec "APPLYING"
if not defined CLAUDE_CODE_GIT_BASH_PATH goto :env_fix_nobash
call :info "Setting CLAUDE_CODE_GIT_BASH_PATH..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $env:CLAUDE_CODE_GIT_BASH_PATH, 'User')"
if !ERRORLEVEL! NEQ 0 goto :env_fix_bashfail
call :ok "Git Bash: !CLAUDE_CODE_GIT_BASH_PATH!"
goto :env_fix_path
:env_fix_nobash
call :warn "Git Bash not found - nothing to set. Install from https://git-scm.com/downloads/win then re-run [F]."
goto :env_fix_path
:env_fix_bashfail
call :err "could not write CLAUDE_CODE_GIT_BASH_PATH - try running this script as the same user that owns the profile"

:env_fix_path
set "AI_DIR=!SCRIPT_DIR!"
call :info "Checking user PATH for !AI_DIR!..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = $env:AI_DIR.TrimEnd('\'); $p = [Environment]::GetEnvironmentVariable('Path','User'); if ($null -eq $p) { $p = '' }; $parts = @($p.Split(';') | Where-Object { $_.Trim() -ne '' }); if (@($parts | ForEach-Object { $_.TrimEnd('\') }) -contains $d) { Write-Host '  [OK] Already in user PATH' } else { [Environment]::SetEnvironmentVariable('Path', (($parts + $d) -join ';'), 'User'); Write-Host '  [OK] Added to user PATH' }"
if !ERRORLEVEL! NEQ 0 call :err "could not update the user PATH - add !AI_DIR! by hand via System Properties / Environment Variables"
echo(
call :ok "Done. Restart your terminal for PATH changes to take effect."
if defined BF_FIXENV goto :quit
call :hold
goto :ai_select

:env_fix_cancel
echo(
call :info "Cancelled. Nothing was changed."
if defined BF_FIXENV goto :quit
call :hold
goto :ai_select


rem ============================================================================
rem  MODEL LIST FETCH (Claude)
rem  The PowerShell body is written to a temp file so batch quoting never has to
rem  survive a round trip through -Command.
rem ============================================================================
:fetch_models
set "PS_SCRIPT=%TEMP%\ai-bat-models-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo     $key = $env:ANTHROPIC_API_KEY >> "!PS_SCRIPT!"
echo     if (-not $key) { >> "!PS_SCRIPT!"
echo         $configPath = Join-Path $env:APPDATA 'claude' 'config.json' >> "!PS_SCRIPT!"
echo         if (Test-Path $configPath) { >> "!PS_SCRIPT!"
echo             $cfg = Get-Content $configPath -Raw ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo             if ($cfg.apiKey) { $key = $cfg.apiKey } >> "!PS_SCRIPT!"
echo         } >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     if (-not $key) { throw 'NO_KEY' } >> "!PS_SCRIPT!"
echo     $headers = @{ 'x-api-key' = $key; 'anthropic-version' = '2023-06-01' } >> "!PS_SCRIPT!"
echo     $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/models?limit=100' -Headers $headers -TimeoutSec 10 >> "!PS_SCRIPT!"
echo     Write-Host '   Models available on your account:' >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     $resp.data ^| Sort-Object id ^| ForEach-Object { >> "!PS_SCRIPT!"
echo         $name = if ($_.display_name) { $_.display_name } else { '' } >> "!PS_SCRIPT!"
echo         Write-Host ('     ' + $_.id.PadRight(45) + $name) >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     Write-Host '   Aliases (always available):' >> "!PS_SCRIPT!"
echo     Write-Host '     opus, sonnet, haiku, opusplan' >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo     if ($_.Exception.Message -eq 'NO_KEY') { >> "!PS_SCRIPT!"
echo         Write-Host '   No ANTHROPIC_API_KEY found - cannot query the live list.' >> "!PS_SCRIPT!"
echo     } else { >> "!PS_SCRIPT!"
echo         Write-Host "   API call failed: $($_.Exception.Message)" >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     Write-Host '   Aliases:  opus, sonnet, haiku, opusplan' >> "!PS_SCRIPT!"
echo     Write-Host '   The menu list lives in ai-models.json next to ai.bat.' >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
del "!PS_SCRIPT!" >nul 2>&1
goto :eof


rem ============================================================================
rem  MODEL MENU LIST (external, editable, updatable)
rem  ai-models.json next to the script feeds the Claude and Codex model menus:
rem      { "claude": [ { "id": "...", "desc": "..." } ], "codex": [ ... ] }
rem  Array order is menu order. PowerShell converts the JSON to pipe-delimited
rem  lines in MDL_LINES; the conversion reruns only when the file's stamp
rem  (mtime+size) changes, so menus render instantly and a mid-run edit still
rem  shows up. choice keys are single digits, so the first 9 entries per engine
rem  are shown; the key hints in the calling menus use the same count (BAT-107).
rem ============================================================================
rem %1 = engine tag. Fills MDL_1..9 / MDD_1..9 and MDL_COUNT; sets MDL_MORE when
rem entries past the ninth were dropped. The explicit clear covers values left
rem over from the other engine's load or inherited from the shell.
:load_models
set "MDL_COUNT=0"
set "MDL_MORE="
for /l %%i in (1,1,9) do ( set "MDL_%%i=" & set "MDD_%%i=" )
if not exist "!MODELS_FILE!" call :write_default_models
if not exist "!MODELS_FILE!" goto :eof
for %%F in ("!MODELS_FILE!") do set "BF_MST=%%~tF %%~zF"
if not "!BF_MST!"=="!MDL_STAMP!" call :parse_models
if not exist "!MDL_LINES!" goto :eof
for /f "usebackq eol=# tokens=1,2,* delims=|" %%A in ("!MDL_LINES!") do (
  if /i "%%A"=="%~1" if not "%%B"=="" (
    if !MDL_COUNT! LSS 9 (
      set /a MDL_COUNT+=1
      set "MDL_!MDL_COUNT!=%%B"
      set "MDD_!MDL_COUNT!=%%C"
    ) else (
      set "MDL_MORE=1"
    )
  )
)
goto :eof

rem JSON -> lines conversion, house temp-ps1 pattern (see :fetch_models). Ids
rem and descriptions are allowlist-filtered in PowerShell because both end up
rem inside CMD, which :run expands with percent semantics (BAT-308). A failed
rem parse keeps the previous lines file so the menus keep working; the stamp is
rem recorded either way so a broken file is not re-parsed on every render.
:parse_models
set "MDL_BAD="
set "MDL_STAMP=!BF_MST!"
set "PS_SCRIPT=%TEMP%\ai-bat-parse-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo     $m = Get-Content -Raw -LiteralPath $env:MODELS_FILE ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo     $out = @() >> "!PS_SCRIPT!"
echo     foreach ($eng in 'claude','codex') { >> "!PS_SCRIPT!"
echo         foreach ($e in @($m.$eng)) { >> "!PS_SCRIPT!"
echo             $id = ([string]$e.id) -replace '[^^A-Za-z0-9._@:/-]', '' >> "!PS_SCRIPT!"
echo             $d  = ([string]$e.desc) -replace '[^^A-Za-z0-9 ._,+/@:-]', '' >> "!PS_SCRIPT!"
echo             if ($id) { $out += ($eng + '^|' + $id + '^|' + $d) } >> "!PS_SCRIPT!"
echo         } >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     [IO.File]::WriteAllLines($env:MDL_LINES, [string[]]$out) >> "!PS_SCRIPT!"
echo     exit 0 >> "!PS_SCRIPT!"
echo } catch { exit 1 } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 set "MDL_BAD=1"
del "!PS_SCRIPT!" >nul 2>&1
goto :eof

rem First run of a standalone copy: materialize the built-in defaults so there
rem is always a file to edit. Keep this block in sync with the ai-models.json
rem shipped in the repo. Existence, not ERRORLEVEL, is the success signal:
rem echo does not touch ERRORLEVEL, so the last menu key's value would lie.
:write_default_models
> "!MODELS_FILE!" (
  echo {
  echo   "comment": "Model menus for ai.bat. Order = menu order; the first 9 per engine are shown. Edit by hand or run: ai.bat --update-models",
  echo   "claude": [
  echo     { "id": "claude-opus-5", "desc": "Opus 5 - newest Opus" },
  echo     { "id": "claude-fable-5", "desc": "Fable 5 - most capable tier" },
  echo     { "id": "claude-opus-4-8", "desc": "Opus 4.8 - adaptive thinking" },
  echo     { "id": "claude-opus-4-7", "desc": "Opus 4.7 - adaptive thinking" },
  echo     { "id": "claude-sonnet-5", "desc": "Sonnet 5 - near-Opus, faster" },
  echo     { "id": "claude-sonnet-4-6", "desc": "Sonnet 4.6 - extended + adaptive" },
  echo     { "id": "claude-haiku-4-5", "desc": "Haiku 4.5 - fast, cost-effective" },
  echo     { "id": "claude-opus-4-6", "desc": "Opus 4.6 - extended + adaptive" }
  echo   ],
  echo   "codex": [
  echo     { "id": "gpt-5.6-sol", "desc": "latest frontier agentic coding model" },
  echo     { "id": "gpt-5.6-terra", "desc": "balanced, for everyday work" },
  echo     { "id": "gpt-5.6-luna", "desc": "fast and affordable" },
  echo     { "id": "gpt-5.5", "desc": "complex coding, research, real work" },
  echo     { "id": "gpt-5.4", "desc": "strong for everyday coding" },
  echo     { "id": "gpt-5.4-mini", "desc": "small, fast, cost-efficient" }
  echo   ]
  echo }
)
if not exist "!MODELS_FILE!" (
  call :warn "could not create !MODELS_FILE! - model menus will only offer custom and skip"
  goto :eof
)
call :info "created !MODELS_FILE! with the default model lists"
goto :eof


rem ============================================================================
rem  MODEL LIST UPDATER
rem  Fetches ai-models.json from AI_BAT_MODELS_URL. The download is validated
rem  as JSON and written to a temp name first, swapped in only on success, so a
rem  failed or garbled fetch never destroys the local file. The fetch itself is
rem  bounded at 10 seconds (BAT-206).
rem ============================================================================
:update_models
call :header "Update model lists"
call :sec "SOURCE"
call :kv "URL " "!AI_BAT_MODELS_URL!"
call :kv "File" "!MODELS_FILE!"
call :sec "UPDATE MODE"
call :item "Y" "From URL"     "download the published list from GitHub"
call :item "L" "Live rebuild" "Anthropic API or models.dev + codex cache"
call :item "N" "Cancel"       "keep the current file"
echo(
call :note "Either mode replaces the local file, including hand edits."
call :foot "[Y] from url   [L] live   [N] cancel" "timeout = no"
call :menu_key "YLN" "N"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="L" goto :update_models_live
if not "!BF_CH!"=="Y" goto :ai_select
echo(
call :sec "FETCHING"
call :models_update_go
call :hold
goto :ai_select
:update_models_live
echo(
call :sec "REBUILDING FROM LIVE SOURCES"
call :models_refresh_go
call :hold
goto :ai_select

rem --update-models / --refresh-models: headless one-shots (BAT-010).
:update_flag
call :models_update_go
set "BF_EXIT=!MDL_UPD_RC!"
goto :cleanup
:refresh_flag
call :models_refresh_go
set "BF_EXIT=!MDL_UPD_RC!"
goto :cleanup

rem AI_BAT_AUTO_UPDATE: refresh at launch, but only when the local list is at
rem least a day old. forfiles /d -1 succeeds exactly when the file's last write
rem is a day or more in the past; on any forfiles error the fetch is skipped.
rem A successful "already up to date" fetch touches the file's mtime so the
rem daily gate does not re-fire on every launch.
:auto_update_check
if not exist "!MODELS_FILE!" goto :auto_update_do
forfiles /p "!SCRIPT_DIR!" /m ai-models.json /d -1 >nul 2>&1 || goto :eof
:auto_update_do
call :info "model list is stale - refreshing (AI_BAT_AUTO_UPDATE is set)"
call :models_update_go
goto :eof

rem Shared fetch. Prints its own status lines and leaves MDL_UPD_RC 0/1.
:models_update_go
set "MDL_UPD_RC=0"
set "PS_SCRIPT=%TEMP%\ai-bat-update-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo     [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 >> "!PS_SCRIPT!"
echo     $url = $env:AI_BAT_MODELS_URL >> "!PS_SCRIPT!"
echo     $dst = $env:MODELS_FILE >> "!PS_SCRIPT!"
echo     Write-Host ('   Fetching ' + $url) >> "!PS_SCRIPT!"
echo     $resp = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing >> "!PS_SCRIPT!"
echo     $json = $resp.Content >> "!PS_SCRIPT!"
echo     if ($json -is [byte[]]) { $json = [Text.Encoding]::UTF8.GetString($json) } >> "!PS_SCRIPT!"
echo     $null = $json ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo     $tmp = $dst + '.new' >> "!PS_SCRIPT!"
echo     [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false)) >> "!PS_SCRIPT!"
echo     $same = $false >> "!PS_SCRIPT!"
echo     if (Test-Path -LiteralPath $dst) { $same = ((Get-FileHash $tmp).Hash -eq (Get-FileHash $dst).Hash) } >> "!PS_SCRIPT!"
echo     if ($same) { Remove-Item -LiteralPath $tmp; (Get-Item -LiteralPath $dst).LastWriteTime = Get-Date; Write-Host '   Already up to date.' } else { Move-Item -LiteralPath $tmp -Destination $dst -Force; Write-Host ('   Updated ' + $dst) } >> "!PS_SCRIPT!"
echo     exit 0 >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo     Write-Host ('   Update failed: ' + $_.Exception.Message) >> "!PS_SCRIPT!"
echo     exit 1 >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
if !ERRORLEVEL! NEQ 0 set "MDL_UPD_RC=1"
del "!PS_SCRIPT!" >nul 2>&1
if "!MDL_UPD_RC!"=="1" call :err "model list update failed - check the URL above and your connection, then retry"
goto :eof

rem Live rebuild. Claude comes from the Anthropic API when a key is available
rem (ANTHROPIC_API_KEY or apiKey in %%APPDATA%%\claude\config.json - same
rem sources as :fetch_models), else from models.dev, a public no-auth model
rem database that uses the vendors' native ids. Codex comes from the picker
rem cache codex itself maintains in ~/.codex/models_cache.json - those are the
rem only slugs "codex -m" accepts, so no website beats it. Any section whose
rem sources are unreachable keeps its current entries; if nothing is reachable
rem the file is left untouched and the exit code is 1. Output is deterministic
rem (no timestamps), so re-running without upstream changes is a no-op commit.
:models_refresh_go
set "MDL_UPD_RC=0"
set "PS_SCRIPT=%TEMP%\ai-bat-refresh-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 >> "!PS_SCRIPT!"
echo $dst = $env:MODELS_FILE >> "!PS_SCRIPT!"
echo $old = $null >> "!PS_SCRIPT!"
echo if (Test-Path -LiteralPath $dst) { try { $old = Get-Content -Raw -LiteralPath $dst ^| ConvertFrom-Json } catch { $old = $null } } >> "!PS_SCRIPT!"
echo $claude = @() >> "!PS_SCRIPT!"
echo $srcC = '' >> "!PS_SCRIPT!"
echo $key = $env:ANTHROPIC_API_KEY >> "!PS_SCRIPT!"
echo if (-not $key) { >> "!PS_SCRIPT!"
echo     $cfg = Join-Path $env:APPDATA 'claude\config.json' >> "!PS_SCRIPT!"
echo     if (Test-Path -LiteralPath $cfg) { try { $c = Get-Content -Raw -LiteralPath $cfg ^| ConvertFrom-Json; if ($c.apiKey) { $key = $c.apiKey } } catch {} } >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if ($key) { >> "!PS_SCRIPT!"
echo     try { >> "!PS_SCRIPT!"
echo         $h = @{ 'x-api-key' = $key; 'anthropic-version' = '2023-06-01' } >> "!PS_SCRIPT!"
echo         $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/models?limit=100' -Headers $h -TimeoutSec 10 >> "!PS_SCRIPT!"
echo         $claude = @($resp.data ^| Select-Object -First 9 ^| ForEach-Object { >> "!PS_SCRIPT!"
echo             $d = [string]$_.created_at; if ($d.Length -ge 10) { $d = $d.Substring(0,10) } >> "!PS_SCRIPT!"
echo             [pscustomobject]@{ id = $_.id; desc = ([string]$_.display_name + ' - ' + $d) } }) >> "!PS_SCRIPT!"
echo         $srcC = 'Anthropic API' >> "!PS_SCRIPT!"
echo     } catch {} >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if (-not $claude) { >> "!PS_SCRIPT!"
echo     try { >> "!PS_SCRIPT!"
echo         $md = Invoke-RestMethod -Uri 'https://models.dev/api.json' -TimeoutSec 15 >> "!PS_SCRIPT!"
echo         $claude = @($md.anthropic.models.PSObject.Properties ^| Sort-Object { [string]$_.Value.release_date } -Descending ^| Select-Object -First 9 ^| ForEach-Object { >> "!PS_SCRIPT!"
echo             [pscustomobject]@{ id = $_.Name; desc = ([string]$_.Value.name + ' - ' + [string]$_.Value.release_date) } }) >> "!PS_SCRIPT!"
echo         $srcC = 'models.dev' >> "!PS_SCRIPT!"
echo     } catch {} >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if (-not $claude -and $old.claude) { $claude = @($old.claude); $srcC = 'kept existing - fetch failed' } >> "!PS_SCRIPT!"
echo $codex = @() >> "!PS_SCRIPT!"
echo $srcX = '' >> "!PS_SCRIPT!"
echo $cc = Join-Path $env:USERPROFILE '.codex\models_cache.json' >> "!PS_SCRIPT!"
echo if (Test-Path -LiteralPath $cc) { >> "!PS_SCRIPT!"
echo     try { >> "!PS_SCRIPT!"
echo         $cj = Get-Content -Raw -LiteralPath $cc ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo         $codex = @($cj.models ^| Where-Object { $_.visibility -eq 'list' } ^| Sort-Object priority ^| Select-Object -First 9 ^| ForEach-Object { >> "!PS_SCRIPT!"
echo             [pscustomobject]@{ id = $_.slug; desc = [string]$_.description } }) >> "!PS_SCRIPT!"
echo         $srcX = 'codex cache' >> "!PS_SCRIPT!"
echo     } catch {} >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if (-not $codex -and $old.codex) { $codex = @($old.codex); $srcX = 'kept existing - no codex cache' } >> "!PS_SCRIPT!"
echo if ((-not $claude) -and (-not $codex)) { Write-Host '   Nothing fetched - file left unchanged.'; exit 1 } >> "!PS_SCRIPT!"
echo $doc = [ordered]@{ comment = 'Model menus for ai.bat. Rebuilt by --refresh-models. Order = menu order; the first 9 per engine are shown.'; claude = $claude; codex = $codex } >> "!PS_SCRIPT!"
echo $json = $doc ^| ConvertTo-Json -Depth 4 >> "!PS_SCRIPT!"
echo $tmp = $dst + '.new' >> "!PS_SCRIPT!"
echo [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false)) >> "!PS_SCRIPT!"
echo $null = Get-Content -Raw -LiteralPath $tmp ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo Move-Item -LiteralPath $tmp -Destination $dst -Force >> "!PS_SCRIPT!"
echo Write-Host ('   claude: ' + $claude.Count + ' models - source: ' + $srcC) >> "!PS_SCRIPT!"
echo Write-Host ('   codex:  ' + $codex.Count + ' models - source: ' + $srcX) >> "!PS_SCRIPT!"
echo Write-Host ('   Wrote ' + $dst) >> "!PS_SCRIPT!"
echo exit 0 >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
if !ERRORLEVEL! NEQ 0 set "MDL_UPD_RC=1"
del "!PS_SCRIPT!" >nul 2>&1
if "!MDL_UPD_RC!"=="1" call :err "live model refresh failed - no source reachable; the local file was not changed"
goto :eof


rem ============================================================================
rem  RENDER
rem  User-supplied text is always echoed through a variable with delayed
rem  expansion, never through %VAR%, so operators in a path or a prompt cannot
rem  execute (BAT-308).
rem ============================================================================
rem %1 = breadcrumb shown on the right of the title bar
:header
call :build
call :clear_screen
call :hr
call :title "%~1"
call :hr
rem CONF is shown only inside the Claude flow. Outside it, a CLAUDE_CONFIG_DIR
rem inherited from the surrounding shell is not this run's choice and printing
rem it reads as one.
set "BF_SHOWCONF="
if "!AI_KIND!"=="claude" if defined CLAUDE_CONFIG_DIR set "BF_SHOWCONF=1"
if not defined BF_COLOR goto :header_plain
echo(   !ESC![!BF_DIM!mDIR !ESC![0m  !REPO_ROOT!
if defined AI_NAME echo(   !ESC![!BF_DIM!mAI  !ESC![0m  !AI_NAME!
if defined BF_SHOWCONF echo(   !ESC![!BF_DIM!mCONF!ESC![0m  !CLAUDE_CONFIG_DIR!
if defined CMD echo(   !ESC![!BF_DIM!mCMD !ESC![0m  !CMD!
goto :eof
:header_plain
echo(   DIR   !REPO_ROOT!
if defined AI_NAME echo(   AI    !AI_NAME!
if defined BF_SHOWCONF echo(   CONF  !CLAUDE_CONFIG_DIR!
if defined CMD echo(   CMD   !CMD!
goto :eof

:hr
echo(  +!BF_HR!+
goto :eof

:rule
if not defined BF_COLOR goto :rule_plain
echo(  !ESC![!BF_DIM!m!BF_RULE!!ESC![0m
goto :eof
:rule_plain
echo(  !BF_RULE!
goto :eof

rem %1 = breadcrumb.  Padding is computed on the plain text so the right border
rem stays put once the escape sequences are inserted (BAT-106).
:title
set "BF_TL=!BF_NAME! !BF_VERSION!!BF_PAD!"
set "BF_TL=!BF_TL:~0,42!"
set "BF_TR=%~1!BF_PAD!"
set "BF_TR=!BF_TR:~0,26!"
if not defined BF_COLOR goto :title_plain
echo(  ^| !ESC![!BF_ACCENT!;1m!BF_TL!!ESC![0m!ESC![!BF_DIM!m!BF_TR!!ESC![0m ^|
goto :eof
:title_plain
echo(  ^| !BF_TL!!BF_TR! ^|
goto :eof

rem %1 = section label, rendered uppercase by the caller
:sec
set "BF_S=%~1"
echo(
if not defined BF_COLOR goto :sec_plain
echo(  !ESC![1m!BF_S!!ESC![0m
goto :eof
:sec_plain
echo(  !BF_S!
goto :eof

rem %1 = key, %2 = label, %3 = hint.  The accent is on the key only.
:item
set "BF_K=%~1"
set "BF_L=%~2!BF_PAD!"
set "BF_L=!BF_L:~0,28!"
set "BF_H=%~3"
if not defined BF_COLOR goto :item_plain
echo(   [!ESC![!BF_ACCENT!m!BF_K!!ESC![0m] !BF_L! !ESC![!BF_DIM!m!BF_H!!ESC![0m
goto :eof
:item_plain
echo(   [!BF_K!] !BF_L! !BF_H!
goto :eof

rem %1 = free-form note line
:note
set "BF_N=%~1"
if not defined BF_COLOR goto :note_plain
echo(       !ESC![!BF_DIM!m!BF_N!!ESC![0m
goto :eof
:note_plain
echo(       !BF_N!
goto :eof

rem %1 = label, %2 = value
:kv
set "BF_KVK=%~1"
set "BF_KVV=%~2"
if not defined BF_COLOR goto :kv_plain
echo(   !ESC![!BF_DIM!m!BF_KVK!!ESC![0m  !BF_KVV!
goto :eof
:kv_plain
echo(   !BF_KVK!  !BF_KVV!
goto :eof

rem %1 = key hints, %2 = right-hand trailer.  The hint set here must match the
rem set handed to choice /c on the following line (BAT-107); :menu_key derives
rem the accepted characters from that same string, so they cannot drift.
:foot
set "BF_FL=%~1!BF_PAD!"
set "BF_FL=!BF_FL:~0,52!"
set "BF_FR=%~2"
echo(
call :rule
if not defined BF_COLOR goto :foot_plain
echo(   !ESC![!BF_DIM!mKEYS!ESC![0m  !BF_FL!  !ESC![!BF_DIM!m!BF_FR!!ESC![0m
goto :eof
:foot_plain
echo(   KEYS  !BF_FL!  !BF_FR!
goto :eof

rem Terminal control goes to stderr, not stdout, so --print-cmd and --help stay
rem clean when piped (BAT-007).
:clear_screen
if defined BF_NONINTERACTIVE goto :eof
if defined BF_COLOR <nul set /p "=!ESC![2J!ESC![H" 1>&2
if not defined BF_COLOR cls
goto :eof


rem ============================================================================
rem  INPUT
rem ============================================================================
rem %1 = key set for choice /c, %2 = key applied on timeout.
rem Leaves the pressed character in BF_CH.  Sets BF_STOP on any path that must
rem not return to a menu (BAT-201, BAT-202, BAT-203).
:menu_key
set "BF_CH="
set /a BF_LOOPS+=1
if !BF_LOOPS! GTR %BF_LOOP_CAP% goto :menu_key_capped
set "BF_KEYS=%~1"
echo(
<nul set /p "=   Select: "
choice /c %~1 /n /t %BF_IDLE_TIMEOUT% /d %~2
set "BF_KEY=!ERRORLEVEL!"
if "!BF_KEY!"=="0" goto :menu_key_cancel
if "!BF_KEY!"=="255" goto :menu_key_failed
set /a BF_KEYI=BF_KEY-1
for %%i in (!BF_KEYI!) do set "BF_CH=!BF_KEYS:~%%i,1!"
echo(
goto :eof
:menu_key_capped
call :err "prompt iteration cap %BF_LOOP_CAP% reached; aborting instead of looping"
set "BF_EXIT=70"
set "BF_STOP=1"
goto :eof
:menu_key_cancel
echo(
set "BF_EXIT=4"
set "BF_STOP=1"
goto :eof
:menu_key_failed
call :err "choice.exe could not read input; run from a real console or pass --ai to skip the menu"
set "BF_EXIT=3"
set "BF_STOP=1"
goto :eof

rem %1 = variable name, %2 = prompt.  Cleared first so a closed or redirected
rem stdin yields an empty value instead of a stale one (BAT-202).
:ask
set "%~1="
if defined BF_NONINTERACTIVE goto :eof
set /p "%~1=   %~2"
goto :eof

rem Bounded hold. Never a bare pause: that waits forever with no console.
rem timeout errors out under redirection instead of hanging, which is what we
rem want here, so its failure is swallowed (BAT-202).
:hold
echo(
timeout /t 15 2>nul
if !ERRORLEVEL! NEQ 0 echo(
goto :eof

rem Printed before any free-text entry that ends up inside CMD. :run launches
rem through percent expansion, which is the only form that runs a command
rem containing shell operators, so text carrying them splits the command.
rem Stated up front rather than detected after the fact.
rem The operators are safe unquoted here: cmd does not treat them as operators
rem inside a quoted argument, and :note echoes via delayed expansion (BAT-308).
:opnote
call :note "Avoid & | < and > in this text - cmd splits the command there."
goto :eof


rem ============================================================================
rem  CONTEXT, ARGUMENTS, ROOT DISCOVERY
rem ============================================================================
:detect_context
set "BF_COLOR="
set "BF_NOCOLOR="
set "BF_NONINTERACTIVE="
set "BF_CP="

rem NO_COLOR: present and non-empty disables color whatever its value (BAT-101).
if defined NO_COLOR if not "%NO_COLOR%"=="" set "BF_NOCOLOR=1"
if /i "%TERM%"=="dumb" set "BF_NOCOLOR=1"

if defined CI set "BF_NONINTERACTIVE=1"
if defined GITHUB_ACTIONS set "BF_NONINTERACTIVE=1"
if defined TF_BUILD set "BF_NONINTERACTIVE=1"
if defined NO_INPUT set "BF_NONINTERACTIVE=1"

rem Without choice there is no bounded wait, so never enter the menu (BAT-204).
where choice >nul 2>&1 || set "BF_NONINTERACTIVE=1"

rem Capture ESC without embedding a raw control byte in the source (BAT-103).
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

if not defined BF_NOCOLOR set "BF_COLOR=1"
if defined BF_NONINTERACTIVE set "BF_COLOR="
if defined FORCE_COLOR if not defined BF_NOCOLOR set "BF_COLOR=1"
goto :eof

:parse_args
if "%~1"=="" goto :eof
set "BF_A=%~1"
if /i "!BF_A!"=="--help"    goto :args_help
if /i "!BF_A!"=="-h"        goto :args_help
if    "!BF_A!"=="/?"        goto :args_help
if /i "!BF_A!"=="--version" goto :args_version
if /i "!BF_A!"=="--no-color"  goto :args_nocolor
if /i "!BF_A!"=="--no-input"  goto :args_noinput
if /i "!BF_A!"=="--yes"       goto :args_yes
if /i "!BF_A!"=="--print-cmd" goto :args_printcmd
if /i "!BF_A!"=="--fix-env"   goto :args_fixenv
if /i "!BF_A!"=="--update-models" goto :args_update
if /i "!BF_A!"=="--refresh-models" goto :args_refresh
if /i "!BF_A!"=="--ai"      goto :args_ai
if /i "!BF_A!"=="--dir"     goto :args_dir
if /i "!BF_A!"=="--model"   goto :args_model
if /i "!BF_A!"=="--effort"  goto :args_effort
if /i "!BF_A!"=="--perm"    goto :args_perm
if /i "!BF_A!"=="--account" goto :args_account
if /i "!BF_A!"=="--extra"   goto :args_extra
call :err "unknown argument '!BF_A!'; try --help"
set "BF_EXIT=2"
goto :eof

:args_help
call :usage
set "BF_STOP=1"
goto :eof
:args_version
echo(!BF_NAME! !BF_VERSION!
set "BF_STOP=1"
goto :eof
:args_nocolor
set "BF_NOCOLOR=1"
set "BF_COLOR="
shift
goto :parse_args
:args_noinput
set "BF_NONINTERACTIVE=1"
set "BF_COLOR="
shift
goto :parse_args
:args_yes
set "BF_ASSUME_YES=1"
shift
goto :parse_args
:args_printcmd
set "BF_PRINT_ONLY=1"
shift
goto :parse_args
:args_fixenv
set "BF_FIXENV=1"
set "BF_ASSUME_YES=1"
shift
goto :parse_args
:args_update
set "BF_UPDATE=1"
shift
goto :parse_args
:args_refresh
set "BF_REFRESH=1"
shift
goto :parse_args
:args_ai
if "%~2"=="" goto :args_ai_missing
if /i "%~2"=="claude"      ( set "AI_KIND=claude" & set "AI_NAME=Claude" )
if /i "%~2"=="codex"       ( set "AI_KIND=codex"  & set "AI_NAME=Codex" )
if /i "%~2"=="gemini"      ( set "AI_KIND=gemini" & set "AI_NAME=Gemini" )
if /i "%~2"=="antigravity" ( set "AI_KIND=agy"    & set "AI_NAME=Antigravity" )
if not defined AI_KIND goto :args_ai_bad
if "!AI_KIND!"=="codex" set "CX_BASE=codex"
shift
shift
goto :parse_args
:args_ai_missing
call :err "--ai needs a value: claude, codex, gemini or antigravity"
set "BF_EXIT=2"
goto :eof
:args_ai_bad
call :err "unknown engine '%~2'; expected claude, codex, gemini or antigravity"
set "BF_EXIT=2"
goto :eof
:args_dir
if "%~2"=="" goto :args_dir_missing
if not exist "%~2\." goto :args_dir_bad
set "AI_BAT_ROOT=%~2"
shift
shift
goto :parse_args
:args_dir_missing
call :err "--dir needs a directory path"
set "BF_EXIT=2"
goto :eof
:args_dir_bad
call :err "not a directory: %~2"
set "BF_EXIT=5"
goto :eof
:args_model
if "%~2"=="" goto :args_val_missing
set "MODEL_FLAG=--model %~2"
set "CX_MODEL= -m %~2"
set "GM_MODEL= -m %~2"
shift
shift
goto :parse_args
:args_effort
if "%~2"=="" goto :args_val_missing
set "EFFORT_FLAG=--effort %~2"
shift
shift
goto :parse_args
:args_perm
if "%~2"=="" goto :args_val_missing
set "PERM_MODE=%~2"
shift
shift
goto :parse_args
:args_account
if "%~2"=="" goto :args_val_missing
if "%~2"=="1" set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc1"
if "%~2"=="2" set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc2"
shift
shift
goto :parse_args
:args_extra
if "%~2"=="" goto :args_val_missing
set "BF_EXTRA=!BF_EXTRA! %~2"
shift
shift
goto :parse_args
:args_val_missing
call :err "!BF_A! needs a value; try --help"
set "BF_EXIT=2"
goto :eof

rem ---------------------------------------------------------------------------
rem  WORKING DIRECTORY
rem  This script is meant to be vendored into a bigger project as a submodule or
rem  a plain copy. The agent should run at the top of that project, not in this
rem  folder, so walk up and use the outermost directory that owns a .git entry.
rem  Override with AI_BAT_ROOT, --dir, or [D] on the confirm screen.
rem ---------------------------------------------------------------------------
:resolve_root
set "REPO_ROOT="
if defined AI_BAT_ROOT if exist "!AI_BAT_ROOT!\." set "REPO_ROOT=!AI_BAT_ROOT!"
if defined REPO_ROOT goto :eof
set "SCAN=!SCRIPT_DIR!"
set "BF_WALK=0"
call :find_root
if not defined REPO_ROOT set "REPO_ROOT=!SCRIPT_DIR!"
goto :eof

rem Walk up from !SCAN! recording the outermost .git owner. .git is a directory
rem in a normal clone and a file in a submodule or worktree, so a plain
rem "if exist" covers both. The counter is a backstop against a pathological
rem path that never reaches a drive root (BAT-201).
:find_root
set /a BF_WALK+=1
if !BF_WALK! GTR %BF_ROOT_CAP% goto :eof
if exist "!SCAN!\.git" set "REPO_ROOT=!SCAN!"
for %%D in ("!SCAN!") do set "PARENT=%%~dpD"
if "!PARENT:~-1!"=="\" set "PARENT=!PARENT:~0,-1!"
if "!PARENT!"=="" goto :eof
if "!PARENT:~-1!"==":" goto :eof
if /i "!PARENT!"=="!SCAN!" goto :eof
set "SCAN=!PARENT!"
goto :find_root

rem ---------------------------------------------------------------------------
rem  GIT BASH AUTO-DETECT (required by Claude on Windows)
rem ---------------------------------------------------------------------------
:detect_git_bash
if defined CLAUDE_CODE_GIT_BASH_PATH goto :eof
if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "CLAUDE_CODE_GIT_BASH_PATH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if defined CLAUDE_CODE_GIT_BASH_PATH goto :eof
if exist "C:\Program Files\Git\bin\bash.exe" set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe"
if defined CLAUDE_CODE_GIT_BASH_PATH goto :eof
if exist "C:\Program Files (x86)\Git\bin\bash.exe" set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files (x86)\Git\bin\bash.exe"
if defined CLAUDE_CODE_GIT_BASH_PATH goto :eof
if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" set "CLAUDE_CODE_GIT_BASH_PATH=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
if defined CLAUDE_CODE_GIT_BASH_PATH goto :eof
for /f "delims=" %%p in ('where bash.exe 2^>nul') do if not defined CLAUDE_CODE_GIT_BASH_PATH set "CLAUDE_CODE_GIT_BASH_PATH=%%p"
goto :eof


rem ============================================================================
rem  MESSAGES
rem  Diagnostics go to stderr so stdout stays parseable (BAT-007).
rem ============================================================================
:err
set "BF_M=%~1"
if not defined BF_COLOR goto :err_plain
1>&2 echo(   !ESC![31mERROR!ESC![0m  !BF_M!
goto :eof
:err_plain
1>&2 echo(   ERROR: !BF_M!
goto :eof

:warn
set "BF_M=%~1"
if not defined BF_COLOR goto :warn_plain
1>&2 echo(   !ESC![!BF_ACCENT!mWARN!ESC![0m   !BF_M!
goto :eof
:warn_plain
1>&2 echo(   WARN: !BF_M!
goto :eof

:info
set "BF_M=%~1"
if not defined BF_COLOR goto :info_plain
1>&2 echo(   !ESC![!BF_DIM!m--^>!ESC![0m    !BF_M!
goto :eof
:info_plain
1>&2 echo(   --^>    !BF_M!
goto :eof

:ok
set "BF_M=%~1"
if not defined BF_COLOR goto :ok_plain
1>&2 echo(   !ESC![32mOK!ESC![0m     !BF_M!
goto :eof
:ok_plain
1>&2 echo(   OK:    !BF_M!
goto :eof

:unreachable
call :err "unhandled selection '!BF_CH!' - the key list and the choice list disagree"
set "BF_EXIT=70"
goto :cleanup

:quit
set "BF_EXIT=0"
goto :cleanup

rem Usage goes to stdout and exits 0 (BAT-004).
:usage
echo(!BF_NAME! !BF_VERSION!
echo(
echo(Launches Claude, Codex, Gemini or Antigravity with the flags you pick.
echo(
echo(Usage: !BF_SELF! [options]
echo(
echo(  With no options it opens the interactive menu.
echo(  With --ai it builds and runs the command directly, no menu.
echo(
echo(Options:
echo(  --ai ^<claude^|codex^|gemini^|antigravity^>   engine to launch
echo(  --account ^<1^|2^>            Claude config profile to use
echo(  --model ^<id^>               model id passed to the engine
echo(  --effort ^<low^|medium^|high^|xhigh^|max^>     Claude effort level
echo(  --perm ^<mode^>              Claude permission mode
echo(  --extra ^<text^>             extra flags appended verbatim
echo(  --dir ^<path^>               working directory to run in
echo(  --print-cmd                print the assembled command, do not run it
echo(  --fix-env                  set git-bash + PATH permanently, then exit
echo(  --update-models            download the model list, then exit
echo(  --refresh-models           rebuild the list from live sources, then exit
echo(  --yes                      skip confirmation prompts
echo(  --no-color                 disable colored output
echo(  --no-input                 never prompt; fail instead
echo(  --version                  print version and exit
echo(  -h, --help, /?             print this help and exit
echo(
echo(Environment:
echo(  AI_BAT_ROOT         working directory override
echo(  AI_BAT_ACCENT       SGR params for the accent color, default 38;5;208
echo(  AI_BAT_MODELS_URL   source URL for model list updates
echo(  AI_BAT_AUTO_UPDATE  refresh the model list at launch, at most once a day
echo(  NO_COLOR            disables color when set and non-empty
echo(  FORCE_COLOR         re-enables color unless NO_COLOR is set
echo(  CI, NO_INPUT        force non-interactive mode
echo(
echo(Files:
echo(  ai-models.json   Claude and Codex model menus, JSON, next to the script.
echo(                   Edit by hand or refresh with --update-models / [U].
echo(                   Created with defaults on first use.
echo(
echo(Exit codes:
echo(  0   success
echo(  1   model list update failed
echo(  2   usage error
echo(  3   missing dependency ^(choice.exe unavailable^)
echo(  4   cancelled by user
echo(  5   precondition failed ^(working directory missing^)
echo(  70  internal error ^(iteration cap tripped^)
echo(  other   exit code of the launched AI CLI, passed through
goto :eof


rem ============================================================================
rem  CLEANUP: every exit path arrives here (BAT-301)
rem  Batch cannot trap Ctrl-C, so this can be skipped entirely if the user
rem  answers Y to "Terminate batch job". The reset is therefore re-emitted after
rem  every render rather than only here, and the cursor is never hidden
rem  (BAT-302).
rem ============================================================================
:cleanup
if defined BF_COLOR <nul set /p "=!ESC![0m!ESC![?25h" 1>&2
if defined BF_CP chcp !BF_CP! >nul 2>&1
if defined MDL_LINES if exist "!MDL_LINES!" del "!MDL_LINES!" >nul 2>&1
1>&2 echo(

rem Hold the window only when double-clicked, and only for a bounded time, so a
rem scripted caller is never left waiting (BAT-202).
set "BF_DC="
echo(!CMDCMDLINE! | find /i "!BF_SELF!" >nul 2>&1 && set "BF_DC=1"
if defined BF_DC if not defined BF_NONINTERACTIVE timeout /t 15 >nul 2>&1

endlocal & exit /b %BF_EXIT%
