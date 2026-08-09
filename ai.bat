@echo off
rem ============================================================================
rem  AI LAUNCHER
rem  Picks an AI CLI (Claude / Codex / Gemini / Antigravity / DeepSeek / any
rem  endpoint of your own), then exposes that engine's own parameters, then
rem  shows the assembled command before running.
rem
rem  Encoding: ASCII / UTF-8 without BOM.  Line endings: CRLF.
rem  Exit codes: see :usage
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- identity --------------------------------------------------------------
set "BF_NAME=AI LAUNCHER"
set "BF_VERSION=2.4"

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

rem ---- Explorer right-click entry --------------------------------------------
rem A per-user shell verb under HKCU\Software\Classes: no elevation, nothing
rem machine-wide, and deleting the two keys deletes every trace. Two keys because
rem Explorer models them separately: the background of a folder, which is also
rem what the desktop is, and a folder that is clicked directly. [R] on the engine
rem menu is the switch; see :ctx_menu.
set "CTX_KEY=Software\Classes\Directory\Background\shell\AILauncher"
set "CTX_KEY2=Software\Classes\Directory\shell\AILauncher"
set "CTX_LABEL=AI Launcher"
set "CTX_SCRIPT=!SCRIPT_DIR!\!BF_SELF!"

rem The icon is drawn once, on install, and cached per user, so this stays a
rem single file with nothing to ship alongside it. Put an ai-launcher.ico next to
rem ai.bat, or point AI_BAT_ICON at any .ico or "file.dll,index" resource, to use
rem your own instead; a supplied icon is never generated over or deleted.
set "CTX_ICON_GEN=%LOCALAPPDATA%\ai-launcher\ai-launcher.ico"
if not defined LOCALAPPDATA set "CTX_ICON_GEN=%TEMP%\ai-launcher.ico"
set "CTX_ICON=!CTX_ICON_GEN!"
if exist "!SCRIPT_DIR!\ai-launcher.ico" set "CTX_ICON=!SCRIPT_DIR!\ai-launcher.ico"
if defined AI_BAT_ICON set "CTX_ICON=!AI_BAT_ICON!"

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
  AX_SHAPE AX_URL AX_KEY AX_KEYVAR AX_MODEL AX_FAST AX_EFFORT AX_SRC AX_IN
  AX_COMPACT AX_KEYNOTE AX_PROBE AX_PAUTH AX_PHEAD AX_CLI AX_URLHINT AX_URLSHOW
  CU_CX
  NEW_ROOT NEW_CMD SCAN PARENT AI_DIR PS_SCRIPT
  MDL_COUNT MDL_MORE MDL_STAMP MDL_BAD MDL_UPD_RC BF_MKEYS BF_MDEF BF_MRANGE
  BF_MST BF_UPDATE BF_REFRESH BF_E1 BF_SHOWAX BF_MASK BF_MK BF_MDLLINE
  BF_CTX_ON BF_CTX_TAG BF_CTX_PATH BF_CTX_HAVE BF_CTX_RC BF_CTXSET
) do set "%%V="

rem An endpoint engine hands Anthropic-shaped names to the claude process it
rem starts, so an ai.bat opened from inside that session would inherit them and
rem quietly point a plain Claude run at that endpoint. AI_BAT_INJECTED marks
rem those names as this script's doing; without it nothing is touched, so a
rem hand-configured proxy survives.
if defined AI_BAT_INJECTED call :ax_reset_env

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
if defined BF_CTXSET goto :ctx_flag

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
if "!AI_KIND!"=="deepseek" call :ds_headless_defaults
if "!AI_KIND!"=="custom" call :cu_headless_defaults
if defined BF_STOP goto :cleanup
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
call :ctx_state
call :header "Select engine"
call :sec "ENGINE"
call :item "1" "Claude"      "Anthropic - full agentic CLI"
call :item "2" "Codex"       "OpenAI - codex CLI, supports --yolo"
call :item "3" "Gemini"      "Google - gemini CLI, supports --yolo"
call :item "4" "Antigravity" "Google - agy terminal agent"
call :item "5" "DeepSeek"    "DeepSeek - their API, claude CLI"
call :item "6" "Custom API"  "any endpoint, claude or codex CLI"
call :sec "SETUP"
call :item "F" "Fix environment" "set git-bash + PATH permanently"
call :item "U" "Update models"   "download the latest model lists"
call :item "R" "Right-click menu" "!BF_CTX_TAG!"
call :foot "1-6   [F] env  [U] models  [R] right-click  [Q] quit" "default 1"
call :menu_key "123456FURQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="F" goto :env_fix
if "!BF_CH!"=="U" goto :update_models
if "!BF_CH!"=="R" goto :ctx_menu
if "!BF_CH!"=="1" goto :claude_flow
if "!BF_CH!"=="2" goto :codex_flow
if "!BF_CH!"=="3" goto :gemini_flow
if "!BF_CH!"=="4" goto :antigravity_flow
if "!BF_CH!"=="5" goto :deepseek_flow
if "!BF_CH!"=="6" goto :custom_flow
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
rem This screen and everything below it are shared with the endpoint engines,
rem which drive the same claude binary; the headers read from AI_NAME so they
rem name the engine the user actually picked.
:cl_effort
call :header "!AI_NAME! / Effort"
call :sec "EFFORT LEVEL"
set "BF_E1=no --effort flag"
if "!AI_KIND!"=="deepseek" set "BF_E1=max, the level DeepSeek's own guide sets"
if "!AI_KIND!"=="custom" set "BF_E1=no CLAUDE_CODE_EFFORT_LEVEL set"
call :item "1" "Default"    "!BF_E1!"
call :item "2" "Low"        "fast, light reasoning"
call :item "3" "Medium"     "standard tasks"
call :item "4" "High"       "complex tasks"
call :item "5" "Extra high" "deep analysis"
call :item "6" "Maximum"    "hardest problems"
call :foot "1-6   [B] back   [Q] quit" "default 1"
call :menu_key "123456BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" if "!AI_KIND!"=="deepseek" goto :ds_fast
if "!BF_CH!"=="B" if "!AI_KIND!"=="custom" goto :cu_fast
if "!BF_CH!"=="B" goto :cl_model
set "EFFORT_FLAG="
set "AX_EFFORT="
rem A third-party endpoint takes the level through CLAUDE_CODE_EFFORT_LEVEL, not
rem through --effort, so the same six keys land in a different carrier. Only
rem DeepSeek has a documented default worth applying to [1].
if "!AI_KIND!"=="deepseek" goto :cl_effort_env
if "!AI_KIND!"=="custom" goto :cl_effort_env
if "!BF_CH!"=="2" set "EFFORT_FLAG=--effort low"
if "!BF_CH!"=="3" set "EFFORT_FLAG=--effort medium"
if "!BF_CH!"=="4" set "EFFORT_FLAG=--effort high"
if "!BF_CH!"=="5" set "EFFORT_FLAG=--effort xhigh"
if "!BF_CH!"=="6" set "EFFORT_FLAG=--effort max"
goto :cl_perm
:cl_effort_env
if "!AI_KIND!"=="deepseek" set "AX_EFFORT=max"
if "!BF_CH!"=="2" set "AX_EFFORT=low"
if "!BF_CH!"=="3" set "AX_EFFORT=medium"
if "!BF_CH!"=="4" set "AX_EFFORT=high"
if "!BF_CH!"=="5" set "AX_EFFORT=xhigh"
if "!BF_CH!"=="6" set "AX_EFFORT=max"

rem --- 3. PERMISSION MODE -----------------------------------------------------
:cl_perm
call :header "!AI_NAME! / Permissions"
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
call :header "!AI_NAME! / Session"
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
call :header "!AI_NAME! / Logging"
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
call :header "!AI_NAME! / Directories"
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
call :header "!AI_NAME! / System prompt"
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
call :header "!AI_NAME! / MCP"
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
call :header "!AI_NAME! / Tools"
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
call :header "!AI_NAME! / Browser"
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
call :header "!AI_NAME! / Worktree"
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
call :header "!AI_NAME! / Startup"
call :sec "STARTUP MODE"
call :item "1" "Normal"    "hooks, plugins, CLAUDE.md as usual"
call :item "2" "Bare"      "--bare, fastest start"
call :item "3" "Safe mode" "--safe-mode, all customizations off"
if "!AI_KIND!"=="deepseek" goto :cl_startup_axnote
if "!AI_KIND!"=="custom" goto :cl_startup_axnote
call :note "Bare skips hooks/plugins/CLAUDE.md and needs ANTHROPIC_API_KEY."
call :note "Account OAuth will NOT work under --bare."
goto :cl_startup_keys
:cl_startup_axnote
call :note "Bare skips hooks/plugins/CLAUDE.md. Your key travels as"
call :note "ANTHROPIC_AUTH_TOKEN, so authentication still works under --bare."
:cl_startup_keys
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
call :header "!AI_NAME! / IDE"
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
if "!BF_CH!"=="B" if "!AI_KIND!"=="custom" goto :cu_model
if "!BF_CH!"=="B" goto :ai_select
set "CX_BASE=codex"
if "!BF_CH!"=="2" set "CX_BASE=codex resume"
if "!BF_CH!"=="3" set "CX_BASE=codex resume --last"
if "!BF_CH!"=="4" set "CX_BASE=codex fork"
if "!BF_CH!"=="5" set "CX_BASE=codex fork --last"
set "CX_NEW=!BF_CH!"
rem A custom endpoint already has its model; the codex model menu would only
rem offer OpenAI ids that endpoint has never heard of.
if "!AI_KIND!"=="custom" goto :cx_appr

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
if "!BF_CH!"=="B" if "!AI_KIND!"=="custom" goto :cx_session
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
rem ============================================================================
rem  ENDPOINT ENGINES: DEEPSEEK AND CUSTOM API
rem  Neither ships a CLI of its own. Both point a CLI you already have at a
rem  different endpoint - the claude binary at an Anthropic Messages API, or the
rem  codex binary at an OpenAI Responses API - so everything after the endpoint
rem  questions is the Claude or the Codex flow itself, not a copy of it.
rem
rem  Both fill the same variables, so one key screen, one applier, one header
rem  block and one effort branch serve both:
rem    AX_SHAPE   anthropic | openai - which CLI and which wire format
rem    AX_URL     base URL of the endpoint
rem    AX_KEY     the key, in memory only
rem    AX_KEYVAR  environment variable the key is remembered under
rem    AX_MODEL   main model id       AX_FAST  cheap model id (anthropic only)
rem    AX_EFFORT  CLAUDE_CODE_EFFORT_LEVEL value (anthropic only)
rem    AX_PROBE   URL the [T] key check GETs, with AX_PAUTH as its auth style
rem  Switching engines from the menu clears all of them (:ax_reset_choices), so
rem  one endpoint's URL, key or model can never leak into another. A key saved
rem  to the environment is re-read on entry, so only pasted ones are forgotten.
rem
rem  The key reaches the environment only at launch (:ax_apply_env), never while
rem  the menus are up: these names decide how every agent in this console
rem  authenticates, and the flow can still be abandoned with [B] or [Q].
rem ============================================================================
rem ============================================================================
:deepseek_flow
set "AI_KIND=deepseek"
set "AI_NAME=DeepSeek"
call :ax_reset_choices
set "AX_SHAPE=anthropic"
set "AX_KEYVAR=DEEPSEEK_API_KEY"
set "AX_URL=https://api.deepseek.com/anthropic"
if defined AI_BAT_DEEPSEEK_URL set "AX_URL=!AI_BAT_DEEPSEEK_URL!"
set "AX_MODEL=deepseek-v4-pro"
set "AX_FAST=deepseek-v4-flash"
rem DeepSeek's own Claude Code guide sets this window; nothing else does.
set "AX_COMPACT=786432"
rem The model list is served in OpenAI shape at the bare host, not under the
rem /anthropic path the agent itself talks to.
set "AX_PROBE=https://api.deepseek.com/models"
set "AX_PAUTH=bearer"
set "AX_KEYNOTE=Keys come from https://platform.deepseek.com/api_keys"
call :ax_pick_up_key
goto :ax_key


rem ============================================================================
rem  CUSTOM API FLOW (any endpoint, driven by the claude or the codex CLI)
rem ============================================================================
:custom_flow
set "AI_KIND=custom"
set "AI_NAME=Custom API"
call :ax_reset_choices
set "AX_KEYVAR=AI_BAT_CUSTOM_KEY"
set "AX_SHAPE=anthropic"
if /i "!AI_BAT_CUSTOM_BACKEND!"=="codex" set "AX_SHAPE=openai"
if defined AI_BAT_CUSTOM_URL set "AX_URL=!AI_BAT_CUSTOM_URL!"
if defined AI_BAT_CUSTOM_MODEL set "AX_MODEL=!AI_BAT_CUSTOM_MODEL!"
set "AX_KEYNOTE=The key is sent to the endpoint above and to nowhere else."
call :ax_pick_up_key

rem --- 0. WHICH CLI -----------------------------------------------------------
:cu_backend
call :header "Custom API / CLI"
call :sec "WHICH CLI DRIVES IT"
call :item "1" "Claude Code" "endpoint speaks the Anthropic Messages API"
call :item "2" "Codex"       "endpoint speaks the OpenAI Responses API"
call :note "Both are a CLI you already have, pointed somewhere else."
call :note "A gateway that only offers OpenAI chat completions fits neither:"
call :note "codex needs the Responses API, claude needs the Messages API."
call :foot "1 2   [B] back   [Q] quit" "default 1"
call :menu_key "12BQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ai_select
set "AX_SHAPE=anthropic"
if "!BF_CH!"=="2" set "AX_SHAPE=openai"

rem --- 1. ENDPOINT ------------------------------------------------------------
:cu_url
call :cu_shape_labels
call :header "Custom API / Endpoint"
call :sec "CURRENT"
call :kv "CLI     " "!AX_CLI!"
call :kv "Base URL" "!AX_URLSHOW!"
call :sec "BASE URL"
call :item "1" "Enter a base URL" "!AX_URLHINT!"
call :item "2" "Keep current"     "!AX_URLSHOW!"
call :note "The CLI appends its own path, so give the root the provider"
call :note "documents: https://api.example.com/v1 or https://gw.example.com/anthropic"
set "BF_MDEF=1"
if defined AX_URL set "BF_MDEF=2"
call :foot "1 2   [B] back   [Q] quit" "default !BF_MDEF!"
call :menu_key "12BQ" "!BF_MDEF!"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cu_backend
if "!BF_CH!"=="2" goto :cu_url_check
call :opnote
call :ask AX_IN "Base URL: "
if not defined AX_IN goto :cu_url
set "AX_URL=!AX_IN!"
set "AX_IN="
call :cu_shape_labels
:cu_url_check
if not defined AX_URL goto :cu_url_missing
rem Delayed expansion, so an operator inside the typed URL is compared, not run.
echo(!AX_URL! | findstr /i /r /c:"^https*://." >nul 2>&1 || goto :cu_url_bad
goto :ax_key
:cu_url_missing
call :err "the endpoint needs a base URL - pick [1] and type one"
call :hold
goto :cu_url
:cu_url_bad
call :err "that does not look like a URL - it should start with http:// or https://"
call :hold
goto :cu_url

rem Everything that differs between the two CLIs, in one place. Rerun whenever
rem the shape or the URL changes.
:cu_shape_labels
set "AX_URLSHOW=not set yet"
if defined AX_URL set "AX_URLSHOW=!AX_URL!"
set "AX_CLI=claude"
set "AX_URLHINT=root that serves /v1/messages"
set "AX_PROBE=!AX_URL!/v1/models"
set "AX_PAUTH=anthropic"
if "!AX_SHAPE!"=="anthropic" goto :eof
set "AX_CLI=codex"
set "AX_URLHINT=root that serves /responses, usually ends in /v1"
set "AX_PROBE=!AX_URL!/models"
set "AX_PAUTH=bearer"
goto :eof


rem ============================================================================
rem  API KEY (shared by both endpoint engines)
rem ============================================================================
:ax_key
call :mask_key "!AX_KEY!"
call :header "!AI_NAME! / API key"
call :sec "CURRENT"
call :kv "Endpoint" "!AX_URL!"
call :kv "Key     " "!BF_MASK!"
call :kv "Source  " "!AX_SRC!"
call :sec "KEY SOURCE"
call :item "1" "Paste a key"      "kept for this run only"
call :item "2" "Paste and save"   "also stores !AX_KEYVAR! for your user"
call :item "3" "Continue"         "use the key shown above"
call :item "T" "Test the key"     "one GET for the endpoint's model list"
call :item "X" "Forget saved key" "clears the stored !AX_KEYVAR!"
call :note "!AX_KEYNOTE!"
call :note "A pasted key is visible while you type it; the next screen clears."
call :foot "1 2 3   [T] test   [X] forget   [B] back   [Q] quit" "default 3"
call :menu_key "123TXBQ" "3"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" if "!AI_KIND!"=="custom" goto :cu_url
if "!BF_CH!"=="B" goto :ai_select
if "!BF_CH!"=="T" goto :ax_key_test
if "!BF_CH!"=="X" goto :ax_key_forget
if "!BF_CH!"=="1" goto :ax_key_paste
if "!BF_CH!"=="2" goto :ax_key_paste_save
if not defined AX_KEY goto :ax_key_none
if "!AI_KIND!"=="custom" goto :cu_model
goto :ds_model

:ax_key_none
call :err "no API key yet - pick [1] or [2] and paste one"
call :hold
goto :ax_key

:ax_key_paste
call :ask AX_IN "API key: "
if not defined AX_IN goto :ax_key
set "AX_KEY=!AX_IN!"
set "AX_IN="
set "AX_SRC=pasted, this run only"
goto :ax_key

:ax_key_paste_save
call :ask AX_IN "API key: "
if not defined AX_IN goto :ax_key
set "AX_KEY=!AX_IN!"
set "AX_IN="
set "AX_SRC=pasted, this run only"
call :key_save
goto :ax_key

:ax_key_test
echo(
call :sec "KEY CHECK"
if not defined AX_KEY goto :ax_key_test_nokey
if not defined AX_URL goto :ax_key_test_nourl
call :ax_probe "   The endpoint answered. Models it lists:"
goto :ax_key_test_done
:ax_key_test_nokey
call :note "No key to test yet - paste one with [1] or [2] first."
goto :ax_key_test_done
:ax_key_test_nourl
call :note "No endpoint to test against yet."
:ax_key_test_done
call :hold
goto :ax_key

rem Written through the environment rather than into the command line, so the key
rem never appears in a process argument list. setx is avoided here for the same
rem reason as in :env_fix - see the note there.
:key_save
echo(
call :info "Saving !AX_KEYVAR! to your user environment..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable($env:AX_KEYVAR, $env:AX_KEY, 'User')"
if !ERRORLEVEL! NEQ 0 goto :key_save_fail
set "!AX_KEYVAR!=!AX_KEY!"
set "AX_SRC=saved as !AX_KEYVAR! for your user"
call :ok "Saved. New terminals pick it up without asking again."
call :hold
goto :eof
:key_save_fail
call :err "could not write !AX_KEYVAR! - the key still works for this run"
set "AX_SRC=pasted, this run only - saving failed"
call :hold
goto :eof

:ax_key_forget
echo(
call :info "Removing the stored !AX_KEYVAR!..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable($env:AX_KEYVAR, $null, 'User')"
if !ERRORLEVEL! NEQ 0 call :err "could not clear it - remove !AX_KEYVAR! via System Properties / Environment Variables"
set "!AX_KEYVAR!="
set "AX_KEY="
set "AX_SRC=none"
call :ok "Stored key cleared. This run has no key until you paste one."
call :hold
goto :ax_key


rem ============================================================================
rem  CUSTOM API: MODEL
rem ============================================================================
:cu_model
call :header "Custom API / Model"
call :load_models custom
call :sec "MODEL"
for /l %%i in (1,1,!MDL_COUNT!) do call :item "%%i" "!MDL_%%i!" "!MDD_%%i!"
call :item "C" "Enter a model id" "asks the endpoint for its list first"
call :item "S" "Keep current"     "!AX_MODEL!"
call :note "Entries under the custom section of ai-models.json show up here."
if defined MDL_BAD call :note "ai-models.json has a JSON error - fix it or re-download via [U]."
if defined MDL_MORE call :note "Only the first 9 custom entries in ai-models.json are shown."
set "BF_MKEYS="
for /l %%i in (1,1,!MDL_COUNT!) do set "BF_MKEYS=!BF_MKEYS!%%i"
set "BF_MDEF=C"
if not "!MDL_COUNT!"=="0" set "BF_MDEF=1"
if defined AX_MODEL set "BF_MDEF=S"
set "BF_MRANGE=1-!MDL_COUNT!   "
if "!MDL_COUNT!"=="1" set "BF_MRANGE=1   "
if "!MDL_COUNT!"=="0" set "BF_MRANGE="
call :foot "!BF_MRANGE![C] enter id   [S] keep   [B] back   [Q] quit" "default !BF_MDEF!"
call :menu_key "!BF_MKEYS!CSBQ" "!BF_MDEF!"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ax_key
if "!BF_CH!"=="C" goto :cu_custom_model
if "!BF_CH!"=="S" goto :cu_model_done
for %%i in (!BF_CH!) do set "AX_MODEL=!MDL_%%i!"
goto :cu_model_done

:cu_custom_model
call :header "Custom API / Model / Enter id"
call :sec "AVAILABLE MODELS"
echo(
call :ax_probe "   Models this endpoint lists:"
echo(
if defined AX_MODEL call :note "Blank entry keeps !AX_MODEL!."
echo(
call :ask AX_IN "Model id: "
if defined AX_IN set "AX_MODEL=!AX_IN!"
set "AX_IN="

:cu_model_done
if not defined AX_MODEL goto :cu_model_missing
rem codex takes the model as a flag, claude takes it as ANTHROPIC_MODEL.
if "!AX_SHAPE!"=="openai" goto :cx_session
goto :cu_fast
:cu_model_missing
call :err "the endpoint needs a model id - pick one or enter it with [C]"
call :hold
goto :cu_model

rem Claude Code reaches for a cheaper model for subagents and background work.
rem Left unset it would ask a non-Anthropic endpoint for a Claude name, so it is
rem always pinned - to the main model unless the endpoint has something cheaper.
:cu_fast
call :header "Custom API / Fast model"
call :sec "FAST AND SUBAGENT MODEL"
call :item "1" "Same as main model" "!AX_MODEL!"
call :item "C" "Enter a model id"   "a cheaper tier, if there is one"
call :kv "Current" "!AX_FAST!"
call :note "Used for the haiku slot, subagents and background work."
call :foot "1   [C] enter id   [B] back   [Q] quit" "default 1"
call :menu_key "1CBQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :cu_model
if "!BF_CH!"=="1" set "AX_FAST=!AX_MODEL!"
if not "!BF_CH!"=="C" goto :cl_effort
call :ask AX_IN "Fast model id: "
if defined AX_IN set "AX_FAST=!AX_IN!"
set "AX_IN="
goto :cl_effort


rem ============================================================================
rem  DEEPSEEK: MODEL
rem  Entries come from ai-models.json (engine tag "deepseek"), same file and same
rem  rules as the Claude and Codex menus.
rem ============================================================================
:ds_model
call :header "DeepSeek / Model"
call :load_models deepseek
call :sec "MODEL"
for /l %%i in (1,1,!MDL_COUNT!) do call :item "%%i" "!MDL_%%i!" "!MDD_%%i!"
call :item "C" "Custom model id" "lists models available on your key"
call :item "S" "Keep current"    "!AX_MODEL!"
call :note "Sent as ANTHROPIC_MODEL; the endpoint has no --model flag."
call :note "Edit ai-models.json next to !BF_SELF! to change this list."
if defined MDL_BAD call :note "ai-models.json has a JSON error - fix it or re-download via [U]."
if defined MDL_MORE call :note "Only the first 9 deepseek entries in ai-models.json are shown."
if "!MDL_COUNT!"=="0" call :note "No deepseek entries in ai-models.json - pick [C] or [S]."
set "BF_MKEYS="
for /l %%i in (1,1,!MDL_COUNT!) do set "BF_MKEYS=!BF_MKEYS!%%i"
set "BF_MDEF=1"
if "!MDL_COUNT!"=="0" set "BF_MDEF=S"
set "BF_MRANGE=1-!MDL_COUNT!   "
if "!MDL_COUNT!"=="1" set "BF_MRANGE=1   "
if "!MDL_COUNT!"=="0" set "BF_MRANGE="
call :foot "!BF_MRANGE![C] custom   [S] keep   [B] back   [Q] quit" "default !BF_MDEF!"
call :menu_key "!BF_MKEYS!CSBQ" "!BF_MDEF!"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ax_key
if "!BF_CH!"=="S" goto :ds_fast
if "!BF_CH!"=="C" goto :ds_custom_model
for %%i in (!BF_CH!) do set "AX_MODEL=!MDL_%%i!"
goto :ds_fast

:ds_custom_model
call :header "DeepSeek / Model / Custom"
call :sec "AVAILABLE MODELS"
echo(
call :ax_probe "   Models available on your key:"
echo(
call :note "Blank entry keeps !AX_MODEL!."
echo(
call :ask AX_IN "Model id: "
if defined AX_IN set "AX_MODEL=!AX_IN!"
set "AX_IN="

rem --- 2. FAST MODEL ----------------------------------------------------------
rem Claude Code reaches for a cheaper model for subagents and background work.
rem Left unset it would ask DeepSeek for a Claude name, so it is always pinned.
:ds_fast
call :header "DeepSeek / Fast model"
call :sec "FAST AND SUBAGENT MODEL"
call :item "1" "deepseek-v4-flash" "the tier DeepSeek recommends here"
call :item "2" "Same as main"      "!AX_MODEL!"
call :item "C" "Custom model id"   "type any id"
call :kv "Current" "!AX_FAST!"
call :foot "1 2   [C] custom   [B] back   [Q] quit" "default 1"
call :menu_key "12CBQ" "1"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="Q" goto :quit
if "!BF_CH!"=="B" goto :ds_model
if "!BF_CH!"=="1" set "AX_FAST=deepseek-v4-flash"
if "!BF_CH!"=="2" set "AX_FAST=!AX_MODEL!"
if not "!BF_CH!"=="C" goto :cl_effort
call :ask AX_IN "Fast model id: "
if defined AX_IN set "AX_FAST=!AX_IN!"
set "AX_IN="

rem --- 3. EVERYTHING ELSE -----------------------------------------------------
rem Effort, permissions, session, logging, directories, system prompt, MCP,
rem tools, browser, worktree, startup and IDE are claude CLI features and behave
rem the same against DeepSeek, so the Claude flow takes it from here.
goto :cl_effort


rem ============================================================================
rem  ENDPOINT ENGINE HELPERS
rem ============================================================================
rem Everything the endpoint engines own, cleared on entry to either of them.
:ax_reset_choices
for %%V in (
  AX_SHAPE AX_URL AX_KEY AX_KEYVAR AX_MODEL AX_FAST AX_EFFORT AX_SRC
  AX_COMPACT AX_KEYNOTE AX_PROBE AX_PAUTH AX_CLI AX_URLHINT AX_URLSHOW AX_IN
  MODEL_FLAG EFFORT_FLAG PERM_MODE
  CL_SESSION CL_VERBOSE CL_ADDDIR CL_SYSPROMPT CL_MCP CL_TOOLS CL_CHROME
  CL_WORKTREE CL_STARTUP CL_IDE
  CX_MODEL CX_APPR CX_SEARCH CX_CD CX_PROMPT CX_NEW
) do set "%%V="
set "CLAUDE_CONFIG_DIR="
set "CX_BASE=codex"
goto :eof

rem A saved key is the one thing that survives switching engines, because it
rem lives in the environment rather than in this run. Read by name, spelled out
rem per engine: resolving a variable whose name is itself in a variable needs a
rem second expansion pass, and that pass would also re-parse the key.
:ax_pick_up_key
set "AX_SRC=none"
if "!AX_KEYVAR!"=="DEEPSEEK_API_KEY" call :ax_pick_deepseek
if "!AX_KEYVAR!"=="AI_BAT_CUSTOM_KEY" call :ax_pick_custom
goto :eof
:ax_pick_deepseek
if not defined DEEPSEEK_API_KEY goto :eof
set "AX_KEY=!DEEPSEEK_API_KEY!"
set "AX_SRC=DEEPSEEK_API_KEY, already in your environment"
goto :eof
:ax_pick_custom
if not defined AI_BAT_CUSTOM_KEY goto :eof
set "AX_KEY=!AI_BAT_CUSTOM_KEY!"
set "AX_SRC=AI_BAT_CUSTOM_KEY, already in your environment"
goto :eof

rem %1 = the secret. Never prints more of it than its ends.
:mask_key
set "BF_MASK=not set - paste one below"
set "BF_MK=%~1"
if not defined BF_MK goto :eof
set "BF_MASK=!BF_MK:~0,6!****!BF_MK:~-4!"
set "BF_MK="
goto :eof

rem Applied at launch only. AI_BAT_INJECTED is the marker the next ai.bat in
rem this console looks for; see the clear block at the top of the script.
:ax_apply_env
if not defined AX_KEY call :ax_pick_up_key
if not defined AX_KEY goto :ax_apply_nokey
if not defined AX_URL goto :ax_apply_nourl
if not defined AX_MODEL goto :ax_apply_nomodel
if "!AX_SHAPE!"=="openai" goto :ax_apply_openai
if not defined AX_FAST set "AX_FAST=!AX_MODEL!"
set "ANTHROPIC_BASE_URL=!AX_URL!"
set "ANTHROPIC_AUTH_TOKEN=!AX_KEY!"
rem An Anthropic key left in the environment would go out as an x-api-key header
rem alongside the bearer token, so it is dropped for this run.
set "ANTHROPIC_API_KEY="
set "ANTHROPIC_MODEL=!AX_MODEL!"
set "ANTHROPIC_DEFAULT_OPUS_MODEL=!AX_MODEL!"
set "ANTHROPIC_DEFAULT_SONNET_MODEL=!AX_MODEL!"
set "ANTHROPIC_DEFAULT_HAIKU_MODEL=!AX_FAST!"
set "CLAUDE_CODE_SUBAGENT_MODEL=!AX_FAST!"
if defined AX_EFFORT set "CLAUDE_CODE_EFFORT_LEVEL=!AX_EFFORT!"
if defined AX_COMPACT set "CLAUDE_CODE_AUTO_COMPACT_WINDOW=!AX_COMPACT!"
set "AI_BAT_INJECTED=1"
goto :ax_apply_done
:ax_apply_openai
rem codex reads the key itself, out of the variable named by the -c overrides
rem :build_codex writes, so that one name is the whole handover. Nothing
rem Anthropic-shaped is set, so nothing needs undoing on the next run either.
set "!AX_KEYVAR!=!AX_KEY!"
:ax_apply_done
rem The key is carried by the names above from here on; no reason for the
rem launched agent to also see it under this script's own name.
set "AX_KEY="
goto :eof
:ax_apply_nokey
call :err "no API key for !AI_NAME! - set !AX_KEYVAR!, or pick the engine from the menu and paste one"
set "BF_EXIT=5"
set "BF_STOP=1"
goto :eof
:ax_apply_nourl
call :err "no endpoint URL for !AI_NAME! - set AI_BAT_CUSTOM_URL, or enter one from the menu"
set "BF_EXIT=5"
set "BF_STOP=1"
goto :eof
:ax_apply_nomodel
call :err "no model id for !AI_NAME! - pass --model, set AI_BAT_CUSTOM_MODEL, or pick one from the menu"
set "BF_EXIT=5"
set "BF_STOP=1"
goto :eof

rem Undoes exactly what :ax_apply_env injected, nothing else.
:ax_reset_env
for %%V in (
  ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL
  CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_AUTO_COMPACT_WINDOW AI_BAT_INJECTED
) do set "%%V="
goto :eof

rem Shown on the launch screen, where the command line alone would not say which
rem endpoint or model is really in play.
:ax_launch_note
call :info "Endpoint !AX_URL! - model !AX_MODEL!"
goto :eof

rem GET AX_PROBE with AX_PAUTH's auth style and report what came back. House
rem temp-ps1 pattern, see :fetch_models; URL, key and heading travel in the
rem environment, so nothing typed by the user lands on a command line.
rem %1 = heading printed above the list on success.
:ax_probe
if not defined AX_KEY goto :ax_probe_nokey
if not defined AX_PROBE goto :ax_probe_nourl
set "AX_PHEAD=%~1"
set "PS_SCRIPT=%TEMP%\ai-bat-probe-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 >> "!PS_SCRIPT!"
echo $h = @{} >> "!PS_SCRIPT!"
echo if ($env:AX_PAUTH -eq 'anthropic') { $h['x-api-key'] = $env:AX_KEY; $h['anthropic-version'] = '2023-06-01' } else { $h['Authorization'] = 'Bearer ' + $env:AX_KEY } >> "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo     $r = Invoke-RestMethod -Uri $env:AX_PROBE -Headers $h -TimeoutSec 15 >> "!PS_SCRIPT!"
echo     Write-Host $env:AX_PHEAD >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     $ids = @(@($r.data) ^| ForEach-Object { [string]$_.id } ^| Where-Object { $_ } ^| Sort-Object) >> "!PS_SCRIPT!"
echo     if ($ids) { $ids ^| ForEach-Object { Write-Host ('     ' + $_) } } >> "!PS_SCRIPT!"
echo     if (-not $ids) { Write-Host '     it answered, but listed no models' } >> "!PS_SCRIPT!"
echo     exit 0 >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo     $code = 0 >> "!PS_SCRIPT!"
echo     if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } >> "!PS_SCRIPT!"
echo     if ($code -eq 401 -or $code -eq 403) { Write-Host ('   ' + $code + ' - the endpoint answered and rejected this key.') } >> "!PS_SCRIPT!"
echo     if ($code -eq 404) { Write-Host '   404 - reachable, but it serves no model list at that path.' } >> "!PS_SCRIPT!"
echo     if ($code -eq 404) { Write-Host '         Normal for many gateways; it says nothing about the key.' } >> "!PS_SCRIPT!"
echo     if ($code -ne 0 -and $code -ne 401 -and $code -ne 403 -and $code -ne 404) { Write-Host ('   HTTP ' + $code + ' - ' + $_.Exception.Message) } >> "!PS_SCRIPT!"
echo     if ($code -eq 0) { Write-Host ('   No answer: ' + $_.Exception.Message) } >> "!PS_SCRIPT!"
echo     exit 1 >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
set "AX_PHEAD="
del "!PS_SCRIPT!" >nul 2>&1
goto :eof
:ax_probe_nokey
call :note "No key set, so the endpoint cannot be queried."
goto :eof
:ax_probe_nourl
call :note "No endpoint set, so there is nothing to query."
goto :eof

rem --ai deepseek / --ai custom skip the menus, so the values the screens would
rem have filled come from the environment here instead.
:ds_headless_defaults
set "AX_SHAPE=anthropic"
set "AX_KEYVAR=DEEPSEEK_API_KEY"
set "AX_URL=https://api.deepseek.com/anthropic"
if defined AI_BAT_DEEPSEEK_URL set "AX_URL=!AI_BAT_DEEPSEEK_URL!"
if not defined AX_MODEL set "AX_MODEL=deepseek-v4-pro"
if not defined AX_FAST set "AX_FAST=deepseek-v4-flash"
if not defined AX_EFFORT set "AX_EFFORT=max"
set "AX_COMPACT=786432"
call :ax_pick_up_key
goto :eof

rem Checked here rather than at launch, because the endpoint is part of the
rem command line for codex: --print-cmd would otherwise hand back a half-written
rem provider override that looks runnable.
:cu_headless_defaults
set "AX_KEYVAR=AI_BAT_CUSTOM_KEY"
set "AX_SHAPE=anthropic"
if /i "!AI_BAT_CUSTOM_BACKEND!"=="codex" set "AX_SHAPE=openai"
if not defined AX_URL if defined AI_BAT_CUSTOM_URL set "AX_URL=!AI_BAT_CUSTOM_URL!"
if not defined AX_MODEL if defined AI_BAT_CUSTOM_MODEL set "AX_MODEL=!AI_BAT_CUSTOM_MODEL!"
if not defined CX_BASE set "CX_BASE=codex"
call :ax_pick_up_key
if not defined AX_URL goto :cu_headless_nourl
if not defined AX_MODEL goto :cu_headless_nomodel
goto :eof
:cu_headless_nourl
call :err "--ai custom needs the endpoint base URL in AI_BAT_CUSTOM_URL"
set "BF_EXIT=5"
set "BF_STOP=1"
goto :eof
:cu_headless_nomodel
call :err "--ai custom needs a model - pass --model or set AI_BAT_CUSTOM_MODEL"
set "BF_EXIT=5"
set "BF_STOP=1"
goto :eof


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
rem The endpoint engines run a binary that is already here; which one depends on
rem the wire format, and the rest of the difference lives in the environment.
if "!AI_KIND!"=="deepseek" goto :build_claude
if "!AI_KIND!"=="custom" if "!AX_SHAPE!"=="openai" goto :build_codex
if "!AI_KIND!"=="custom" goto :build_claude
goto :eof

:build_claude
set "CMD=claude --dangerously-skip-permissions"
if defined PERM_MODE set "CMD=claude --permission-mode !PERM_MODE!"
rem Against a third-party endpoint the model and the effort level travel as
rem ANTHROPIC_MODEL and CLAUDE_CODE_EFFORT_LEVEL (:ax_apply_env); the flags would
rem only fight them, so --model and --effort are left off that command line.
if "!AI_KIND!"=="claude" if defined MODEL_FLAG set "CMD=!CMD! !MODEL_FLAG!"
if "!AI_KIND!"=="claude" if defined EFFORT_FLAG set "CMD=!CMD! !EFFORT_FLAG!"
set "CMD=!CMD!!CL_SESSION!!CL_VERBOSE!!CL_ADDDIR!!CL_SYSPROMPT!!CL_MCP!"
set "CMD=!CMD!!CL_TOOLS!!CL_CHROME!!CL_WORKTREE!!CL_STARTUP!!CL_IDE!!BF_EXTRA!"
goto :eof

rem A custom provider is described entirely on the command line, so the user's
rem own ~/.codex/config.toml is never touched. codex parses each -c value as
rem TOML and falls back to the raw string, and it rejects a provider with no
rem name, so both are spelled out. wire_api is left at its default: this codex
rem accepts only "responses".
:build_codex
set "CU_CX="
if not "!AI_KIND!"=="custom" goto :build_codex_go
set "CU_CX= -c model_provider=aibat -c model_providers.aibat.name=aibat"
set "CU_CX=!CU_CX! -c model_providers.aibat.base_url=!AX_URL!"
set "CU_CX=!CU_CX! -c model_providers.aibat.env_key=!AX_KEYVAR!"
set "CX_MODEL="
if defined AX_MODEL set "CX_MODEL= -m !AX_MODEL!"
:build_codex_go
set "CMD=!CX_BASE!!CU_CX!!CX_MODEL!!CX_APPR!!CX_SEARCH!!CX_CD!!BF_EXTRA!!CX_PROMPT!"
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
if "!AI_KIND!"=="deepseek" call :ax_apply_env
if "!AI_KIND!"=="custom" call :ax_apply_env
if defined BF_STOP goto :cleanup
call :info "Starting !AI_NAME! in !REPO_ROOT!"
if "!AI_KIND!"=="deepseek" call :ax_launch_note
if "!AI_KIND!"=="custom" call :ax_launch_note
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
rem  EXPLORER RIGHT-CLICK ENTRY
rem  The global switch for "AI Launcher" in the Windows context menu. On means
rem  the two HKCU verbs exist, off means they do not; there is no third state and
rem  no config file, because the registry already is the setting.
rem
rem  Explorer substitutes %V with the folder that was clicked, and pushd rather
rem  than cd is used so a UNC path still becomes the working directory. cmd /s
rem  strips exactly the outer quote pair and passes the rest through untouched,
rem  which is what keeps the two inner quoted paths intact.
rem ============================================================================
rem Probes the registry instead of caching a flag: the entry can be removed from
rem outside this script, so the menu has to report what is actually installed.
rem BF_CTX_HAVE additionally says whether the installed entry points at this copy
rem of ai.bat - a moved script, or a second vendored copy, leaves it clear.
:ctx_state
set "BF_CTX_ON="
set "BF_CTX_TAG=OFF - not installed"
set "BF_CTX_PATH="
set "BF_CTX_HAVE="
reg query "HKCU\!CTX_KEY!\command" /ve >nul 2>&1 || goto :eof
set "BF_CTX_ON=1"
set "BF_CTX_TAG=ON  - desktop and folder menus"
for /f "tokens=2,*" %%A in ('reg query "HKCU\!CTX_KEY!\command" /ve 2^>nul ^| find "REG_"') do set "BF_CTX_PATH=%%B"
echo(!BF_CTX_PATH! | find /i "!CTX_SCRIPT!" >nul 2>&1 && set "BF_CTX_HAVE=1"
goto :eof

:ctx_menu
call :ctx_state
call :header "Right-click menu"
call :sec "WHAT THIS ADDS"
call :note "An 'AI Launcher' entry in the Windows right-click menu, on the desktop,"
call :note "on empty space inside a folder, and on a folder itself. Clicking it opens"
call :note "this launcher with that folder as the working directory."
echo(
call :kv "State " "!BF_CTX_TAG!"
call :kv "Script" "!CTX_SCRIPT!"
call :kv "Icon  " "!CTX_ICON!"
call :kv "Keys  " "HKCU\!CTX_KEY!"
call :kv "      " "HKCU\!CTX_KEY2!"
if defined BF_CTX_ON if not defined BF_CTX_HAVE call :warn "the installed entry runs a different ai.bat - [E] re-points it at this one"
echo(
call :note "Per-user registry only, so no admin rights and no machine-wide change."
call :note "Windows 11 lists third-party entries under 'Show more options' (Shift+F10)."
call :sec "SWITCH"
call :item "E" "Enable"  "install the entry, or re-point it here"
call :item "D" "Disable" "remove it from Explorer again"
call :item "B" "Back"    "engine menu"
call :foot "[E] enable   [D] disable   [B] back" "timeout = back"
call :menu_key "EDB" "B"
if defined BF_STOP goto :cleanup
if "!BF_CH!"=="E" goto :ctx_enable
if "!BF_CH!"=="D" goto :ctx_disable
goto :ai_select

:ctx_enable
echo(
call :sec "INSTALLING"
call :ctx_install
call :hold
goto :ctx_menu

:ctx_disable
echo(
call :sec "REMOVING"
call :ctx_remove
call :hold
goto :ctx_menu

rem --context-menu on|off: the same two operations without the menu (BAT-010).
:ctx_flag
if "!BF_CTXSET!"=="off" goto :ctx_flag_off
call :ctx_install
set "BF_EXIT=!BF_CTX_RC!"
goto :cleanup
:ctx_flag_off
call :ctx_remove
set "BF_EXIT=!BF_CTX_RC!"
goto :cleanup

rem The PowerShell body is written to a temp file so batch quoting never has to
rem survive a round trip through -Command (same reason as :fetch_models). The
rem icon is drawn with GDI+ and packed into a multi-size .ico by hand: an ICONDIR
rem header, one ICONDIRENTRY per size, then the PNG payloads, which Explorer has
rem accepted inside .ico files since Vista. Any failure there is not fatal - the
rem entry falls back to the cmd.exe icon and still installs.
:ctx_install
set "BF_CTX_RC=0"
set "PS_SCRIPT=%TEMP%\ai-bat-ctx-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo $icon = $env:CTX_ICON >> "!PS_SCRIPT!"
echo $draw = $true >> "!PS_SCRIPT!"
echo if ($icon -match ',') { $draw = $false } >> "!PS_SCRIPT!"
echo if (Test-Path -LiteralPath $icon) { $draw = $false } >> "!PS_SCRIPT!"
echo if ($draw) { >> "!PS_SCRIPT!"
echo   try { >> "!PS_SCRIPT!"
echo     $dir = Split-Path -Parent $icon >> "!PS_SCRIPT!"
echo     if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force } >> "!PS_SCRIPT!"
echo     Add-Type -AssemblyName System.Drawing >> "!PS_SCRIPT!"
echo     $sizes = @(256,64,48,32,16) >> "!PS_SCRIPT!"
echo     $blobs = @() >> "!PS_SCRIPT!"
echo     foreach ($s in $sizes) { >> "!PS_SCRIPT!"
echo       $bmp = New-Object Drawing.Bitmap -ArgumentList $s, $s >> "!PS_SCRIPT!"
echo       $g = [Drawing.Graphics]::FromImage($bmp) >> "!PS_SCRIPT!"
echo       $g.SmoothingMode = 'AntiAlias' >> "!PS_SCRIPT!"
echo       $g.TextRenderingHint = 'AntiAliasGridFit' >> "!PS_SCRIPT!"
echo       $g.Clear([Drawing.Color]::Transparent) >> "!PS_SCRIPT!"
echo       $m = [single][Math]::Max(1, $s / 16) >> "!PS_SCRIPT!"
echo       $w = [single]($s - 2 * $m) >> "!PS_SCRIPT!"
echo       $d = [single][Math]::Max(2, $s / 5) >> "!PS_SCRIPT!"
echo       $p = New-Object Drawing.Drawing2D.GraphicsPath >> "!PS_SCRIPT!"
echo       $p.AddArc($m, $m, $d, $d, 180, 90) >> "!PS_SCRIPT!"
echo       $p.AddArc($m + $w - $d, $m, $d, $d, 270, 90) >> "!PS_SCRIPT!"
echo       $p.AddArc($m + $w - $d, $m + $w - $d, $d, $d, 0, 90) >> "!PS_SCRIPT!"
echo       $p.AddArc($m, $m + $w - $d, $d, $d, 90, 90) >> "!PS_SCRIPT!"
echo       $p.CloseFigure() >> "!PS_SCRIPT!"
echo       $g.FillPath((New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(255, 26, 26, 30))), $p) >> "!PS_SCRIPT!"
rem At 16 pixels - the size Explorer actually draws in a context menu - a border
rem costs a fifth of the width and buys nothing, so that size drops it and spends
rem the room on the letters instead.
echo       $ratio = 0.5 >> "!PS_SCRIPT!"
echo       if ($s -gt 16) { $g.DrawPath((New-Object Drawing.Pen -ArgumentList ([Drawing.Color]::FromArgb(255, 255, 135, 0)), ([single][Math]::Max(1, $s / 24))), $p) } else { $ratio = 0.7 } >> "!PS_SCRIPT!"
echo       $f = New-Object Drawing.Font -ArgumentList 'Segoe UI', ([single]($s * $ratio)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel) >> "!PS_SCRIPT!"
echo       $sf = New-Object Drawing.StringFormat >> "!PS_SCRIPT!"
echo       $sf.Alignment = 'Center' >> "!PS_SCRIPT!"
echo       $sf.LineAlignment = 'Center' >> "!PS_SCRIPT!"
echo       $box = New-Object Drawing.RectangleF -ArgumentList 0, 0, $s, $s >> "!PS_SCRIPT!"
echo       $g.DrawString('AI', $f, (New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(255, 255, 150, 45))), $box, $sf) >> "!PS_SCRIPT!"
echo       $g.Dispose() >> "!PS_SCRIPT!"
echo       $ms = New-Object IO.MemoryStream >> "!PS_SCRIPT!"
echo       $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png) >> "!PS_SCRIPT!"
echo       $bmp.Dispose() >> "!PS_SCRIPT!"
echo       $blobs += ,$ms.ToArray() >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     $out = New-Object IO.MemoryStream >> "!PS_SCRIPT!"
echo     $bw = New-Object IO.BinaryWriter -ArgumentList $out >> "!PS_SCRIPT!"
echo     $bw.Write([uint16]0) >> "!PS_SCRIPT!"
echo     $bw.Write([uint16]1) >> "!PS_SCRIPT!"
echo     $bw.Write([uint16]$sizes.Count) >> "!PS_SCRIPT!"
echo     $off = 6 + 16 * $sizes.Count >> "!PS_SCRIPT!"
echo     for ($i = 0; $i -lt $sizes.Count; $i++) { >> "!PS_SCRIPT!"
echo       $n = $sizes[$i] >> "!PS_SCRIPT!"
echo       if ($n -ge 256) { $n = 0 } >> "!PS_SCRIPT!"
echo       $bw.Write([byte]$n) >> "!PS_SCRIPT!"
echo       $bw.Write([byte]$n) >> "!PS_SCRIPT!"
echo       $bw.Write([byte]0) >> "!PS_SCRIPT!"
echo       $bw.Write([byte]0) >> "!PS_SCRIPT!"
echo       $bw.Write([uint16]1) >> "!PS_SCRIPT!"
echo       $bw.Write([uint16]32) >> "!PS_SCRIPT!"
echo       $bw.Write([uint32]$blobs[$i].Length) >> "!PS_SCRIPT!"
echo       $bw.Write([uint32]$off) >> "!PS_SCRIPT!"
echo       $off = $off + $blobs[$i].Length >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     foreach ($b in $blobs) { $bw.Write($b) } >> "!PS_SCRIPT!"
echo     $bw.Flush() >> "!PS_SCRIPT!"
echo     [IO.File]::WriteAllBytes($icon, $out.ToArray()) >> "!PS_SCRIPT!"
echo     $bw.Dispose() >> "!PS_SCRIPT!"
echo     Write-Host ('   Icon drawn: ' + $icon) >> "!PS_SCRIPT!"
echo   } catch { >> "!PS_SCRIPT!"
echo     $icon = (Join-Path $env:SystemRoot 'System32\cmd.exe') + ',0' >> "!PS_SCRIPT!"
echo     Write-Host ('   Could not draw the icon, using the cmd.exe one: ' + $_.Exception.Message) >> "!PS_SCRIPT!"
echo   } >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
rem --dir carries the clicked folder, and it has to: :resolve_root walks up from
rem the script's own location, never from the current directory, so without it a
rem right-click in someone else's project would still run the agent in this repo.
rem The pushd is on top of that so the console itself opens there too, which is
rem what any relative path typed into [D] or [E] will then resolve against.
echo $cmd = 'cmd.exe /s /c "pushd "%%V" && "' + $env:CTX_SCRIPT + '" --dir "%%V""' >> "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo   foreach ($k in @($env:CTX_KEY, $env:CTX_KEY2)) { >> "!PS_SCRIPT!"
echo     $rk = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($k) >> "!PS_SCRIPT!"
echo     $rk.SetValue('', $env:CTX_LABEL) >> "!PS_SCRIPT!"
echo     $rk.SetValue('Icon', $icon) >> "!PS_SCRIPT!"
echo     $rk.Close() >> "!PS_SCRIPT!"
echo     $ck = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($k + '\command') >> "!PS_SCRIPT!"
echo     $ck.SetValue('', $cmd) >> "!PS_SCRIPT!"
echo     $ck.Close() >> "!PS_SCRIPT!"
echo     Write-Host ('   Wrote HKCU\' + $k) >> "!PS_SCRIPT!"
echo   } >> "!PS_SCRIPT!"
echo   Write-Host ('   Runs: ' + $cmd) >> "!PS_SCRIPT!"
echo   exit 0 >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo   Write-Host ('   Failed: ' + $_.Exception.Message) >> "!PS_SCRIPT!"
echo   exit 1 >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
if !ERRORLEVEL! NEQ 0 set "BF_CTX_RC=1"
del "!PS_SCRIPT!" >nul 2>&1
if "!BF_CTX_RC!"=="1" call :err "could not write the right-click entry - HKCU\Software\Classes may be restricted by policy"
if "!BF_CTX_RC!"=="0" call :ok "Right-click menu is on. It shows up immediately, no sign-out needed."
goto :eof

rem The generated icon is deleted with the keys so switching this off leaves
rem nothing behind; an icon you supplied yourself is never touched, and neither
rem is the folder unless it is the one this script made and it is now empty.
:ctx_remove
set "BF_CTX_RC=0"
set "PS_SCRIPT=%TEMP%\ai-bat-ctx-%RANDOM%%RANDOM%.ps1"
echo $ErrorActionPreference = 'Stop' > "!PS_SCRIPT!"
echo try { >> "!PS_SCRIPT!"
echo   foreach ($k in @($env:CTX_KEY, $env:CTX_KEY2)) { >> "!PS_SCRIPT!"
echo     [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($k, $false) >> "!PS_SCRIPT!"
echo     Write-Host ('   Cleared HKCU\' + $k) >> "!PS_SCRIPT!"
echo   } >> "!PS_SCRIPT!"
echo   $gen = $env:CTX_ICON_GEN >> "!PS_SCRIPT!"
echo   if ($gen -and (Test-Path -LiteralPath $gen)) { >> "!PS_SCRIPT!"
echo     Remove-Item -LiteralPath $gen -Force >> "!PS_SCRIPT!"
echo     Write-Host ('   Deleted the cached icon') >> "!PS_SCRIPT!"
echo     $dir = Split-Path -Parent $gen >> "!PS_SCRIPT!"
echo     if ((Split-Path -Leaf $dir) -eq 'ai-launcher' -and -not (Get-ChildItem -LiteralPath $dir -Force)) { Remove-Item -LiteralPath $dir -Force } >> "!PS_SCRIPT!"
echo   } >> "!PS_SCRIPT!"
echo   exit 0 >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo   Write-Host ('   Failed: ' + $_.Exception.Message) >> "!PS_SCRIPT!"
echo   exit 1 >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
if !ERRORLEVEL! NEQ 0 set "BF_CTX_RC=1"
del "!PS_SCRIPT!" >nul 2>&1
if "!BF_CTX_RC!"=="1" call :err "could not remove the right-click entry - delete HKCU\!CTX_KEY! by hand with regedit"
if "!BF_CTX_RC!"=="0" call :ok "Right-click menu is off. Nothing is left in the registry."
goto :eof


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
rem  ai-models.json next to the script feeds the claude, codex, deepseek and
rem  custom model menus:
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
echo     foreach ($eng in 'claude','codex','deepseek','custom') { >> "!PS_SCRIPT!"
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
  echo   ],
  echo   "deepseek": [
  echo     { "id": "deepseek-v4-pro", "desc": "V4 Pro - reasoning and agentic work" },
  echo     { "id": "deepseek-v4-flash", "desc": "V4 Flash - lower latency, cheaper" }
  echo   ],
  echo   "custom": []
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
rem only slugs "codex -m" accepts, so no website beats it. DeepSeek comes from
rem models.dev, which carries names and release dates, falling back to the bare
rem id list at api.deepseek.com/models when DEEPSEEK_API_KEY is set. Any section whose
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
echo $md = $null >> "!PS_SCRIPT!"
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
echo $deep = @() >> "!PS_SCRIPT!"
echo $srcD = '' >> "!PS_SCRIPT!"
echo if ($null -eq $md) { try { $md = Invoke-RestMethod -Uri 'https://models.dev/api.json' -TimeoutSec 15 } catch {} } >> "!PS_SCRIPT!"
echo if ($md) { >> "!PS_SCRIPT!"
echo     try { >> "!PS_SCRIPT!"
echo         $deep = @($md.deepseek.models.PSObject.Properties ^| Sort-Object { [string]$_.Value.release_date } -Descending ^| Select-Object -First 9 ^| ForEach-Object { >> "!PS_SCRIPT!"
echo             [pscustomobject]@{ id = $_.Name; desc = ([string]$_.Value.name + ' - ' + [string]$_.Value.release_date) } }) >> "!PS_SCRIPT!"
echo         $srcD = 'models.dev' >> "!PS_SCRIPT!"
echo     } catch {} >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if ((-not $deep) -and $env:DEEPSEEK_API_KEY) { >> "!PS_SCRIPT!"
echo     try { >> "!PS_SCRIPT!"
echo         $hd = @{ Authorization = ('Bearer ' + $env:DEEPSEEK_API_KEY) } >> "!PS_SCRIPT!"
echo         $rd = Invoke-RestMethod -Uri 'https://api.deepseek.com/models' -Headers $hd -TimeoutSec 10 >> "!PS_SCRIPT!"
echo         $deep = @($rd.data ^| Sort-Object id ^| Select-Object -First 9 ^| ForEach-Object { >> "!PS_SCRIPT!"
echo             [pscustomobject]@{ id = $_.id; desc = 'available on your DeepSeek key' } }) >> "!PS_SCRIPT!"
echo         $srcD = 'DeepSeek API' >> "!PS_SCRIPT!"
echo     } catch {} >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"
echo if (-not $deep -and $old.deepseek) { $deep = @($old.deepseek); $srcD = 'kept existing - fetch failed' } >> "!PS_SCRIPT!"
echo if ((-not $claude) -and (-not $codex) -and (-not $deep)) { Write-Host '   Nothing fetched - file left unchanged.'; exit 1 } >> "!PS_SCRIPT!"
rem The custom section is hand-written by definition - no upstream to fetch it
rem from - so a rebuild carries it through untouched instead of dropping it.
echo $cust = @() >> "!PS_SCRIPT!"
echo if ($old.custom) { $cust = @($old.custom) } >> "!PS_SCRIPT!"
echo $doc = [ordered]@{ comment = 'Model menus for ai.bat. Rebuilt by --refresh-models. Order = menu order; the first 9 per engine are shown. The custom list is yours and is kept as is.'; claude = $claude; codex = $codex; deepseek = $deep; custom = $cust } >> "!PS_SCRIPT!"
echo $json = $doc ^| ConvertTo-Json -Depth 4 >> "!PS_SCRIPT!"
echo $tmp = $dst + '.new' >> "!PS_SCRIPT!"
echo [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false)) >> "!PS_SCRIPT!"
echo $null = Get-Content -Raw -LiteralPath $tmp ^| ConvertFrom-Json >> "!PS_SCRIPT!"
echo Move-Item -LiteralPath $tmp -Destination $dst -Force >> "!PS_SCRIPT!"
echo Write-Host ('   claude: ' + $claude.Count + ' models - source: ' + $srcC) >> "!PS_SCRIPT!"
echo Write-Host ('   codex:  ' + $codex.Count + ' models - source: ' + $srcX) >> "!PS_SCRIPT!"
echo Write-Host ('   deepseek: ' + $deep.Count + ' models - source: ' + $srcD) >> "!PS_SCRIPT!"
echo Write-Host ('   custom: ' + $cust.Count + ' models - kept from the existing file') >> "!PS_SCRIPT!"
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
rem An endpoint engine's command line says "claude" or "codex" and little else,
rem so the endpoint and the model it will really use belong on screen next to it.
set "BF_SHOWAX="
if "!AI_KIND!"=="deepseek" set "BF_SHOWAX=1"
if "!AI_KIND!"=="custom" set "BF_SHOWAX=1"
if defined BF_SHOWAX call :header_ax
if not defined BF_COLOR goto :header_plain
echo(   !ESC![!BF_DIM!mDIR !ESC![0m  !REPO_ROOT!
if defined AI_NAME echo(   !ESC![!BF_DIM!mAI  !ESC![0m  !AI_NAME!
if defined BF_SHOWCONF echo(   !ESC![!BF_DIM!mCONF!ESC![0m  !CLAUDE_CONFIG_DIR!
if defined BF_SHOWAX echo(   !ESC![!BF_DIM!mAPI !ESC![0m  !BF_MASK!  at  !AX_URLSHOW!
if defined BF_SHOWAX echo(   !ESC![!BF_DIM!mMDL !ESC![0m  !BF_MDLLINE!
if defined CMD echo(   !ESC![!BF_DIM!mCMD !ESC![0m  !CMD!
goto :eof
:header_plain
echo(   DIR   !REPO_ROOT!
if defined AI_NAME echo(   AI    !AI_NAME!
if defined BF_SHOWCONF echo(   CONF  !CLAUDE_CONFIG_DIR!
if defined BF_SHOWAX echo(   API   !BF_MASK!  at  !AX_URLSHOW!
if defined BF_SHOWAX echo(   MDL   !BF_MDLLINE!
if defined CMD echo(   CMD   !CMD!
goto :eof

rem Only the anthropic shape has a second model to name.
:header_ax
call :mask_key "!AX_KEY!"
set "AX_URLSHOW=not set yet"
if defined AX_URL set "AX_URLSHOW=!AX_URL!"
set "BF_MDLLINE=not set yet"
if defined AX_MODEL set "BF_MDLLINE=!AX_MODEL!"
if "!AX_SHAPE!"=="anthropic" if defined AX_FAST set "BF_MDLLINE=!BF_MDLLINE!  fast: !AX_FAST!"
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
if /i "!BF_A!"=="--context-menu" goto :args_ctxmenu
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
:args_ctxmenu
if "%~2"=="" goto :args_ctx_bad
if /i "%~2"=="on"  set "BF_CTXSET=on"
if /i "%~2"=="off" set "BF_CTXSET=off"
if not defined BF_CTXSET goto :args_ctx_bad
shift
shift
goto :parse_args
:args_ctx_bad
call :err "--context-menu needs on or off"
set "BF_EXIT=2"
goto :eof
:args_ai
if "%~2"=="" goto :args_ai_missing
if /i "%~2"=="claude"      ( set "AI_KIND=claude" & set "AI_NAME=Claude" )
if /i "%~2"=="codex"       ( set "AI_KIND=codex"  & set "AI_NAME=Codex" )
if /i "%~2"=="gemini"      ( set "AI_KIND=gemini" & set "AI_NAME=Gemini" )
if /i "%~2"=="antigravity" ( set "AI_KIND=agy"    & set "AI_NAME=Antigravity" )
if /i "%~2"=="deepseek"    ( set "AI_KIND=deepseek" & set "AI_NAME=DeepSeek" )
if /i "%~2"=="custom"      ( set "AI_KIND=custom"   & set "AI_NAME=Custom API" )
if not defined AI_KIND goto :args_ai_bad
if "!AI_KIND!"=="codex" set "CX_BASE=codex"
shift
shift
goto :parse_args
:args_ai_missing
call :err "--ai needs a value: claude, codex, gemini, antigravity, deepseek or custom"
set "BF_EXIT=2"
goto :eof
:args_ai_bad
call :err "unknown engine '%~2'; expected claude, codex, gemini, antigravity, deepseek or custom"
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
set "AX_MODEL=%~2"
shift
shift
goto :parse_args
:args_effort
if "%~2"=="" goto :args_val_missing
set "EFFORT_FLAG=--effort %~2"
set "AX_EFFORT=%~2"
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
echo(Launches Claude, Codex, Gemini, Antigravity, DeepSeek or any endpoint of your
echo(own, with the flags you pick.
echo(
echo(Usage: !BF_SELF! [options]
echo(
echo(  With no options it opens the interactive menu.
echo(  With --ai it builds and runs the command directly, no menu.
echo(
echo(  deepseek and custom install nothing: they point the claude CLI at an
echo(  Anthropic Messages endpoint, or the codex CLI at an OpenAI Responses one.
echo(  The menu asks for the endpoint and key; --ai reads them from the
echo(  environment instead ^(DEEPSEEK_API_KEY, or the AI_BAT_CUSTOM_* set^).
echo(
echo(Options:
echo(  --ai ^<claude^|codex^|gemini^|antigravity^|deepseek^|custom^>   engine to launch
echo(  --account ^<1^|2^>            Claude config profile to use
echo(  --model ^<id^>               model id passed to the engine
echo(  --effort ^<low^|medium^|high^|xhigh^|max^>     any claude-driven engine
echo(  --perm ^<mode^>              Claude permission mode
echo(  --extra ^<text^>             extra flags appended verbatim
echo(  --dir ^<path^>               working directory to run in
echo(  --print-cmd                print the assembled command, do not run it
echo(  --fix-env                  set git-bash + PATH permanently, then exit
echo(  --update-models            download the model list, then exit
echo(  --refresh-models           rebuild the list from live sources, then exit
echo(  --context-menu ^<on^|off^>     add or remove the Explorer right-click entry
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
echo(  AI_BAT_ICON         icon for the right-click entry: an .ico, or
echo(                      "file.dll,index". Default: one drawn on install
echo(  DEEPSEEK_API_KEY    key for the DeepSeek engine; [5] can store it for you
echo(  AI_BAT_DEEPSEEK_URL override the DeepSeek endpoint, default
echo(                      https://api.deepseek.com/anthropic
echo(  AI_BAT_CUSTOM_KEY   key for the Custom API engine; [6] can store it
echo(  AI_BAT_CUSTOM_URL   base URL for the Custom API engine
echo(  AI_BAT_CUSTOM_MODEL model id for the Custom API engine
echo(  AI_BAT_CUSTOM_BACKEND  claude ^(default^) or codex - which CLI drives it
echo(  NO_COLOR            disables color when set and non-empty
echo(  FORCE_COLOR         re-enables color unless NO_COLOR is set
echo(  CI, NO_INPUT        force non-interactive mode
echo(
echo(Files:
echo(  ai-models.json   Model menus for claude, codex, deepseek and custom, JSON,
echo(                   next to the script. Edit by hand or refresh with
echo(                   --update-models / [U]; the custom list is only ever yours.
echo(                   Created with defaults on first use.
echo(
echo(Exit codes:
echo(  0   success
echo(  1   model list update, or right-click menu change, failed
echo(  2   usage error
echo(  3   missing dependency ^(choice.exe unavailable^)
echo(  4   cancelled by user
echo(  5   precondition failed ^(missing directory, endpoint, key or model^)
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
