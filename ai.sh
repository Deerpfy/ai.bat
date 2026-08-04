#!/usr/bin/env bash
# =============================================================================
#  AI LAUNCHER  (macOS / Linux port of ai.bat)
#  Picks an AI CLI (Claude / Codex / Gemini / Antigravity), then exposes that
#  engine's own parameters, then shows the assembled command before running.
#
#  Same menus, same flags, same exit codes as ai.bat. Written for the bash 3.2
#  that ships with macOS, so no associative arrays and no ${var^^}.
#  Exit codes: see usage()
# =============================================================================

set -u

# ---- identity ---------------------------------------------------------------
BF_NAME="AI LAUNCHER"
BF_VERSION="2.2"

# Resolved before anything else: the model list and [F] fix env both key off the
# directory this script lives in, not the repo it ends up running the agent in.
BF_SELF="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# The editable model-menu list lives next to the script, not in the resolved
# repo root, so a vendored copy keeps its own list. It is converted to
# pipe-delimited lines in MDL_LINES once per change (see parse_models and
# load_models); the menus read only the lines file, so they stay instant.
MODELS_FILE="$SCRIPT_DIR/ai-models.json"
MDL_LINES=""

# Where --update-models and [U] download the list from. Point this at any URL
# that serves the JSON: raw.githubusercontent.com needs no setup, a GitHub
# Pages site works the same way.
: "${AI_BAT_MODELS_URL:=https://raw.githubusercontent.com/Deerpfy/ai.bat/main/ai-models.json}"

# ---- safety limits ----------------------------------------------------------
BF_LOOP_CAP=400
BF_IDLE_TIMEOUT=300
BF_ROOT_CAP=64
[ -n "${AI_BAT_TIMEOUT:-}" ] && BF_IDLE_TIMEOUT="$AI_BAT_TIMEOUT"

# ---- state ------------------------------------------------------------------
BF_EXIT=0
BF_LOOPS=0
BF_STOP=""
BF_ASSUME_YES=""
BF_PRINT_ONLY=""
BF_FIXENV=""
BF_UPDATE=""
BF_REFRESH=""
BF_EXTRA=""
BF_CH=""
BF_COLOR=""
BF_NOCOLOR=""
BF_NONINTERACTIVE=""
AI_KIND=""
AI_NAME=""
AI_EDITED=""
CMD=""
REPO_ROOT=""
STEP=""

# The launcher exports these to the CLI it starts, so a second run from inside
# that session would inherit them and apply them as silent defaults. Clear every
# name the script owns before anything reads one.
MODEL_FLAG=""; EFFORT_FLAG=""; PERM_MODE=""; CUSTOM_MODEL=""
CL_SESSION=""; CL_VERBOSE=""; CL_ADDDIR=""; CL_SYSPROMPT=""; CL_MCP=""
CL_TOOLS=""; CL_CHROME=""; CL_WORKTREE=""; CL_STARTUP=""; CL_IDE=""
CX_BASE="codex"; CX_MODEL=""; CX_APPR=""; CX_SEARCH=""; CX_CD=""; CX_PROMPT=""
CX_NEW=""
GM_MODEL=""; GM_APPR=""; GM_SANDBOX=""; GM_SESS=""; GM_WT=""; GM_DIRS=""
GM_DEBUG=""; GM_PROMPT=""
AG_SESS=""; AG_PERM=""; AG_SB=""; AG_DIR=""; AG_PROMPT=""
MDL_COUNT=0; MDL_MORE=""; MDL_STAMP=""; MDL_BAD=""; MDL_UPD_RC=0
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"

# ---- accent: orange.  Override with AI_BAT_ACCENT (e.g. 33 for basic yellow)
BF_ACCENT="38;5;208"
BF_DIM="38;5;244"
[ -n "${AI_BAT_ACCENT:-}" ] && BF_ACCENT="$AI_BAT_ACCENT"

ESC=$'\033'
BF_HR="----------------------------------------------------------------------"
BF_RULE="$BF_HR--"


# =============================================================================
#  RENDER
# =============================================================================
# $1 = breadcrumb shown on the right of the title bar
header() {
  build
  clear_screen
  hr
  title "$1"
  hr
  # CONF is shown only inside the Claude flow. Outside it, a CLAUDE_CONFIG_DIR
  # inherited from the surrounding shell is not this run's choice and printing
  # it reads as one.
  local showconf=""
  [ "$AI_KIND" = "claude" ] && [ -n "$CLAUDE_CONFIG_DIR" ] && showconf=1
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[%smDIR %s[0m  %s\n' "$ESC" "$BF_DIM" "$ESC" "$REPO_ROOT"
    [ -n "$AI_NAME" ] && printf '   %s[%smAI  %s[0m  %s\n' "$ESC" "$BF_DIM" "$ESC" "$AI_NAME"
    [ -n "$showconf" ] && printf '   %s[%smCONF%s[0m  %s\n' "$ESC" "$BF_DIM" "$ESC" "$CLAUDE_CONFIG_DIR"
    [ -n "$CMD" ] && printf '   %s[%smCMD %s[0m  %s\n' "$ESC" "$BF_DIM" "$ESC" "$CMD"
  else
    printf '   DIR   %s\n' "$REPO_ROOT"
    [ -n "$AI_NAME" ] && printf '   AI    %s\n' "$AI_NAME"
    [ -n "$showconf" ] && printf '   CONF  %s\n' "$CLAUDE_CONFIG_DIR"
    [ -n "$CMD" ] && printf '   CMD   %s\n' "$CMD"
  fi
  return 0
}

hr() { printf '  +%s+\n' "$BF_HR"; }

rule() {
  if [ -n "$BF_COLOR" ]; then
    printf '  %s[%sm%s%s[0m\n' "$ESC" "$BF_DIM" "$BF_RULE" "$ESC"
  else
    printf '  %s\n' "$BF_RULE"
  fi
}

# $1 = breadcrumb.  Padding is computed on the plain text so the right border
# stays put once the escape sequences are inserted.
title() {
  local tl tr
  tl=$(printf '%-42.42s' "$BF_NAME $BF_VERSION")
  tr=$(printf '%-26.26s' "$1")
  if [ -n "$BF_COLOR" ]; then
    printf '  | %s[%s;1m%s%s[0m%s[%sm%s%s[0m |\n' \
      "$ESC" "$BF_ACCENT" "$tl" "$ESC" "$ESC" "$BF_DIM" "$tr" "$ESC"
  else
    printf '  | %s%s |\n' "$tl" "$tr"
  fi
}

# $1 = section label, rendered uppercase by the caller
sec() {
  printf '\n'
  if [ -n "$BF_COLOR" ]; then
    printf '  %s[1m%s%s[0m\n' "$ESC" "$1" "$ESC"
  else
    printf '  %s\n' "$1"
  fi
}

# $1 = key, $2 = label, $3 = hint.  The accent is on the key only.
item() {
  local lbl
  lbl=$(printf '%-28.28s' "$2")
  if [ -n "$BF_COLOR" ]; then
    printf '   [%s[%sm%s%s[0m] %s %s[%sm%s%s[0m\n' \
      "$ESC" "$BF_ACCENT" "$1" "$ESC" "$lbl" "$ESC" "$BF_DIM" "$3" "$ESC"
  else
    printf '   [%s] %s %s\n' "$1" "$lbl" "$3"
  fi
}

# $1 = free-form note line
note() {
  if [ -n "$BF_COLOR" ]; then
    printf '       %s[%sm%s%s[0m\n' "$ESC" "$BF_DIM" "$1" "$ESC"
  else
    printf '       %s\n' "$1"
  fi
}

# $1 = label, $2 = value
kv() {
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[%sm%s%s[0m  %s\n' "$ESC" "$BF_DIM" "$1" "$ESC" "$2"
  else
    printf '   %s  %s\n' "$1" "$2"
  fi
}

# $1 = key hints, $2 = right-hand trailer.  The hint set here must match the set
# handed to menu_key on the following line; menu_key derives the accepted
# characters from its own argument, so keep the two in step.
foot() {
  local fl
  fl=$(printf '%-52.52s' "$1")
  printf '\n'
  rule
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[%smKEYS%s[0m  %s  %s[%sm%s%s[0m\n' \
      "$ESC" "$BF_DIM" "$ESC" "$fl" "$ESC" "$BF_DIM" "$2" "$ESC"
  else
    printf '   KEYS  %s  %s\n' "$fl" "$2"
  fi
}

# Terminal control goes to stderr, not stdout, so --print-cmd and --help stay
# clean when piped.
clear_screen() {
  [ -n "$BF_NONINTERACTIVE" ] && return 0
  if [ -n "$BF_COLOR" ]; then
    printf '%s[2J%s[H' "$ESC" "$ESC" >&2
  else
    command clear 2>/dev/null || true
  fi
}


# =============================================================================
#  MESSAGES
#  Diagnostics go to stderr so stdout stays parseable.
# =============================================================================
err() {
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[31mERROR%s[0m  %s\n' "$ESC" "$ESC" "$1" >&2
  else
    printf '   ERROR: %s\n' "$1" >&2
  fi
}
warn() {
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[%smWARN%s[0m   %s\n' "$ESC" "$BF_ACCENT" "$ESC" "$1" >&2
  else
    printf '   WARN: %s\n' "$1" >&2
  fi
}
info() {
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[%sm-->%s[0m    %s\n' "$ESC" "$BF_DIM" "$ESC" "$1" >&2
  else
    printf '   -->    %s\n' "$1" >&2
  fi
}
ok() {
  if [ -n "$BF_COLOR" ]; then
    printf '   %s[32mOK%s[0m     %s\n' "$ESC" "$ESC" "$1" >&2
  else
    printf '   OK:    %s\n' "$1" >&2
  fi
}

unreachable() {
  err "unhandled selection '$BF_CH' - the key list and the menu list disagree"
  BF_EXIT=70
  BF_STOP=1
}


# =============================================================================
#  INPUT
# =============================================================================
# $1 = accepted key set, $2 = key applied on timeout.
# Leaves the pressed character in BF_CH.  Sets BF_STOP on any path that must not
# return to a menu.
menu_key() {
  local keys="$1" defkey="$2" ch rc
  BF_CH=""
  BF_LOOPS=$((BF_LOOPS + 1))
  if [ "$BF_LOOPS" -gt "$BF_LOOP_CAP" ]; then
    err "prompt iteration cap $BF_LOOP_CAP reached; aborting instead of looping"
    BF_EXIT=70; BF_STOP=1; return 0
  fi
  printf '\n'
  if [ -n "$BF_NONINTERACTIVE" ]; then
    err "no interactive console available; pass --ai <claude|codex|gemini|antigravity> or --help"
    BF_EXIT=3; BF_STOP=1; return 0
  fi
  while :; do
    printf '   Select: '
    ch=""
    IFS= read -rsn1 -t "$BF_IDLE_TIMEOUT" ch
    rc=$?
    if [ "$rc" -gt 128 ]; then
      # timeout: the documented default applies
      BF_CH="$defkey"; printf '%s\n\n' "$BF_CH"; return 0
    fi
    if [ "$rc" -ne 0 ]; then
      # stdin closed or Ctrl-D: never fall through to a menu
      printf '\n'
      BF_EXIT=4; BF_STOP=1; return 0
    fi
    # bare Enter takes the default, matching choice /d
    if [ -z "$ch" ]; then
      BF_CH="$defkey"; printf '%s\n\n' "$BF_CH"; return 0
    fi
    ch=$(printf '%s' "$ch" | tr '[:lower:]' '[:upper:]')
    case "$keys" in
      *"$ch"*) BF_CH="$ch"; printf '%s\n\n' "$BF_CH"; return 0 ;;
    esac
    printf '\r\033[K' 2>/dev/null || printf '\n'
  done
}

# $1 = variable name, $2 = prompt.  Cleared first so a closed or redirected
# stdin yields an empty value instead of a stale one.
ask() {
  local __name="$1" __val=""
  eval "$__name=''"
  [ -n "$BF_NONINTERACTIVE" ] && return 0
  IFS= read -r -p "   $2" __val || __val=""
  eval "$__name=\$__val"
  return 0
}

# Bounded hold. Never an unbounded wait: that hangs with no console.
hold() {
  printf '\n'
  [ -n "$BF_NONINTERACTIVE" ] && return 0
  printf '   Press any key to continue (15s)... '
  IFS= read -rsn1 -t 15 _ 2>/dev/null || true
  printf '\n'
  return 0
}

# Printed before any free-text entry that ends up inside CMD. run_cmd launches
# through eval, which is the only form that runs a command containing shell
# operators, so text carrying them splits the command. Stated up front rather
# than detected after the fact.
opnote() {
  note 'Avoid & | < > ; and ` in this text - the shell splits the command there.'
}


# =============================================================================
#  TOP LEVEL: AI SELECTION
# =============================================================================
m_engine() {
  AI_KIND=""; AI_NAME=""; AI_EDITED=""; CMD=""
  header "Select engine"
  sec "ENGINE"
  item "1" "Claude"      "Anthropic - full agentic CLI"
  item "2" "Codex"       "OpenAI - codex CLI, supports --yolo"
  item "3" "Gemini"      "Google - gemini CLI, supports --yolo"
  item "4" "Antigravity" "Google - agy terminal agent"
  sec "SETUP"
  item "F" "Fix environment" "add this folder to PATH permanently"
  item "U" "Update models"   "download the latest model lists"
  foot "1 2 3 4   [F] fix env   [U] update   [Q] quit" "default 1"
  menu_key "1234FUQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit ;;
    F) STEP=env_fix ;;
    U) STEP=update_models ;;
    1) claude_init; STEP=cl_account ;;
    2) codex_init;  STEP=cx_session ;;
    3) gemini_init; STEP=gm_model ;;
    4) agy_init;    STEP=ag_session ;;
    *) unreachable ;;
  esac
}


# =============================================================================
# =============================================================================
#  CLAUDE FLOW
# =============================================================================
# =============================================================================
claude_init() {
  AI_KIND="claude"; AI_NAME="Claude"
  CLAUDE_CONFIG_DIR=""
  MODEL_FLAG=""; EFFORT_FLAG=""; PERM_MODE=""
  CL_SESSION=""; CL_VERBOSE=""; CL_ADDDIR=""; CL_SYSPROMPT=""; CL_MCP=""
  CL_TOOLS=""; CL_CHROME=""; CL_WORKTREE=""; CL_STARTUP=""; CL_IDE=""
}

# --- 0. ACCOUNT --------------------------------------------------------------
m_cl_account() {
  header "Claude / Account"
  sec "ACCOUNT"
  item "1" "Account 1"  "primary profile,  .claude-acc1"
  item "2" "Account 2"  "fallback profile, .claude-acc2"
  item "3" "Default"    "no account switch"
  item "A" "Auth setup" "first-time login for both accounts"
  foot "1 2 3   [A] auth   [B] back   [Q] quit" "default 1"
  menu_key "123ABQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=engine; return 0 ;;
    A) STEP=auth_setup; return 0 ;;
    1) CLAUDE_CONFIG_DIR="$HOME/.claude-acc1" ;;
    2) CLAUDE_CONFIG_DIR="$HOME/.claude-acc2" ;;
    3) CLAUDE_CONFIG_DIR="" ;;
  esac
  STEP=cl_model
}

# --- 1. MODEL ----------------------------------------------------------------
# Menu entries come from ai-models.json (engine tag "claude") and are reread on
# every render, so an edit to the file shows up immediately.
m_cl_model() {
  local i keys="" def="1" range=""
  header "Claude / Model"
  load_models claude
  sec "MODEL"
  i=1
  while [ "$i" -le "$MDL_COUNT" ]; do
    eval "item \"\$i\" \"\$MDL_ID_$i\" \"\$MDL_DESC_$i\""
    keys="$keys$i"
    i=$((i + 1))
  done
  item "C" "Custom model ID" "lists models available on your key"
  item "S" "Skip"            "no --model flag"
  note "Edit ai-models.json next to $BF_SELF to change this list."
  [ -n "$MDL_BAD" ] && note "ai-models.json has a JSON error - fix it or re-download via [U]."
  [ -n "$MDL_MORE" ] && note "Only the first 9 claude entries in ai-models.json are shown."
  [ "$MDL_COUNT" = "0" ] && note "No claude entries in ai-models.json - pick [C] or [S]."
  range="1-$MDL_COUNT   "
  [ "$MDL_COUNT" = "1" ] && range="1   "
  [ "$MDL_COUNT" = "0" ] && { range=""; def="C"; }
  foot "$range[C] custom   [S] skip   [B] back   [Q] quit" "default $def"
  menu_key "${keys}CSBQ" "$def"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_account; return 0 ;;
  esac
  MODEL_FLAG=""
  case "$BF_CH" in
    C) STEP=cl_custom_model; return 0 ;;
    S) STEP=cl_effort; return 0 ;;
    *) eval "MODEL_FLAG=\"--model \$MDL_ID_$BF_CH\"" ;;
  esac
  STEP=cl_effort
}

m_cl_custom_model() {
  header "Claude / Model / Custom"
  sec "AVAILABLE MODELS"
  printf '\n'
  fetch_models
  printf '\n'
  note "Tip: /model inside Claude switches models mid-session."
  note "Blank entry keeps the previous choice."
  printf '\n'
  ask CUSTOM_MODEL "Model ID: "
  [ -n "$CUSTOM_MODEL" ] && MODEL_FLAG="--model $CUSTOM_MODEL"
  STEP=cl_effort
}

# --- 2. EFFORT ---------------------------------------------------------------
m_cl_effort() {
  header "Claude / Effort"
  sec "EFFORT LEVEL"
  item "1" "Default"    "no --effort flag"
  item "2" "Low"        "fast, light reasoning"
  item "3" "Medium"     "standard tasks"
  item "4" "High"       "complex tasks"
  item "5" "Extra high" "deep analysis"
  item "6" "Maximum"    "hardest problems"
  foot "1-6   [B] back   [Q] quit" "default 1"
  menu_key "123456BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_model; return 0 ;;
  esac
  EFFORT_FLAG=""
  case "$BF_CH" in
    2) EFFORT_FLAG="--effort low" ;;
    3) EFFORT_FLAG="--effort medium" ;;
    4) EFFORT_FLAG="--effort high" ;;
    5) EFFORT_FLAG="--effort xhigh" ;;
    6) EFFORT_FLAG="--effort max" ;;
  esac
  STEP=cl_perm
}

# --- 3. PERMISSION MODE ------------------------------------------------------
m_cl_perm() {
  header "Claude / Permissions"
  sec "PERMISSION MODE"
  item "1" "bypassPermissions" "--dangerously-skip-permissions"
  item "2" "dontAsk"           "auto-approve, no prompts"
  item "3" "acceptEdits"       "auto edits, prompt for commands"
  item "4" "manual"            "prompt for sensitive actions"
  item "5" "plan"              "show plan first, then execute"
  item "6" "auto"              "auto-approve safe, ask on risky"
  foot "1-6   [B] back   [Q] quit" "default 1"
  menu_key "123456BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_effort; return 0 ;;
  esac
  PERM_MODE=""
  case "$BF_CH" in
    2) PERM_MODE="dontAsk" ;;
    3) PERM_MODE="acceptEdits" ;;
    4) PERM_MODE="manual" ;;
    5) PERM_MODE="plan" ;;
    6) PERM_MODE="auto" ;;
  esac
  STEP=cl_session
}

# --- 4. SESSION --------------------------------------------------------------
m_cl_session() {
  local sid sname pr
  header "Claude / Session"
  sec "SESSION"
  item "1" "New session"      "default"
  item "2" "Continue last"    "-c"
  item "3" "Resume specific"  "-r <id|name>"
  item "4" "New, custom name" "-n <name>"
  item "5" "Continue as fork" "-c --fork-session, new id"
  item "6" "Resume from PR"   "--from-pr, blank = picker"
  foot "1-6   [B] back   [Q] quit" "default 1"
  menu_key "123456BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_perm; return 0 ;;
  esac
  CL_SESSION=""
  case "$BF_CH" in
    2) CL_SESSION=" -c" ;;
    5) CL_SESSION=" -c --fork-session" ;;
    3) ask sid "Session ID or name: "; [ -n "$sid" ] && CL_SESSION=" -r $sid" ;;
    4) ask sname "Session name: ";     [ -n "$sname" ] && CL_SESSION=" -n $sname" ;;
    6) ask pr "PR number or URL (blank = picker): "
       CL_SESSION=" --from-pr"
       [ -n "$pr" ] && CL_SESSION=" --from-pr $pr" ;;
  esac
  STEP=cl_verbose
}

# --- 5. VERBOSE / DEBUG ------------------------------------------------------
m_cl_verbose() {
  local cats
  header "Claude / Logging"
  sec "VERBOSE / DEBUG"
  item "1" "Normal"         "default"
  item "2" "Verbose"        "--verbose"
  item "3" "Debug"          "--debug"
  item "4" "Debug + filter" "--debug <categories>"
  foot "1-4   [B] back   [Q] quit" "default 1"
  menu_key "1234BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_session; return 0 ;;
  esac
  CL_VERBOSE=""
  case "$BF_CH" in
    2) CL_VERBOSE=" --verbose" ;;
    3) CL_VERBOSE=" --debug" ;;
    4) ask cats "Debug categories (comma-separated): "
       CL_VERBOSE=" --debug"
       [ -n "$cats" ] && CL_VERBOSE=" --debug $cats" ;;
  esac
  STEP=cl_adddir
}

# --- 6. ADDITIONAL DIRECTORIES -----------------------------------------------
m_cl_adddir() {
  local dirs
  header "Claude / Directories"
  sec "ADDITIONAL WORKING DIRECTORIES"
  item "1" "None"            "default"
  item "2" "Add directories" "--add-dir"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_verbose; return 0 ;;
  esac
  CL_ADDDIR=""
  if [ "$BF_CH" = "2" ]; then
    ask dirs "Directory paths (space-separated): "
    [ -n "$dirs" ] && CL_ADDDIR=" --add-dir $dirs"
  fi
  STEP=cl_sysprompt
}

# --- 7. SYSTEM PROMPT --------------------------------------------------------
m_cl_sysprompt() {
  local txt
  header "Claude / System prompt"
  sec "SYSTEM PROMPT"
  item "1" "Default"          "use CLAUDE.md"
  item "2" "Append text"      "--append-system-prompt"
  item "3" "Replace entirely" "--system-prompt"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_adddir; return 0 ;;
  esac
  CL_SYSPROMPT=""
  case "$BF_CH" in
    2) opnote; ask txt "Text to append: "
       [ -n "$txt" ] && CL_SYSPROMPT=" --append-system-prompt \"$txt\"" ;;
    3) opnote; ask txt "Replacement system prompt: "
       [ -n "$txt" ] && CL_SYSPROMPT=" --system-prompt \"$txt\"" ;;
  esac
  STEP=cl_mcp
}

# --- 8. MCP ------------------------------------------------------------------
m_cl_mcp() {
  local file
  header "Claude / MCP"
  sec "MCP SERVER CONFIG"
  item "1" "None"            "default"
  item "2" "Load config"     "--mcp-config <file>"
  item "3" "Strict MCP only" "--strict-mcp-config --mcp-config"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_sysprompt; return 0 ;;
  esac
  CL_MCP=""
  if [ "$BF_CH" != "1" ]; then
    ask file "MCP config file path: "
    if [ -n "$file" ]; then
      [ "$BF_CH" = "2" ] && CL_MCP=" --mcp-config $file"
      [ "$BF_CH" = "3" ] && CL_MCP=" --strict-mcp-config --mcp-config $file"
    fi
  fi
  STEP=cl_tools
}

# --- 9. TOOL RESTRICTIONS ----------------------------------------------------
m_cl_tools() {
  local list
  header "Claude / Tools"
  sec "TOOL RESTRICTIONS"
  item "1" "All tools"     "default"
  item "2" "Specific only" "--tools <list>"
  item "3" "No tools"      "--tools with an empty list"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_mcp; return 0 ;;
  esac
  CL_TOOLS=""
  [ "$BF_CH" = "3" ] && CL_TOOLS=" --tools \"\""
  if [ "$BF_CH" = "2" ]; then
    note "Bash Edit Read Write Glob Grep WebFetch WebSearch Task NotebookEdit"
    printf '\n'
    ask list "Tool names (comma-separated): "
    [ -n "$list" ] && CL_TOOLS=" --tools \"$list\""
  fi
  STEP=cl_chrome
}

# --- 10. CHROME --------------------------------------------------------------
m_cl_chrome() {
  header "Claude / Browser"
  sec "CHROME INTEGRATION"
  item "1" "Default" "no flag"
  item "2" "Enable"  "--chrome"
  item "3" "Disable" "--no-chrome"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_tools; return 0 ;;
  esac
  CL_CHROME=""
  [ "$BF_CH" = "2" ] && CL_CHROME=" --chrome"
  [ "$BF_CH" = "3" ] && CL_CHROME=" --no-chrome"
  STEP=cl_worktree
}

# --- 11. GIT WORKTREE --------------------------------------------------------
m_cl_worktree() {
  local name
  header "Claude / Worktree"
  sec "GIT WORKTREE"
  item "1" "None"            "work in this checkout"
  item "2" "New worktree"    "-w, isolated repo copy"
  item "3" "Worktree + tmux" "-w --tmux, needs tmux"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_chrome; return 0 ;;
  esac
  CL_WORKTREE=""
  if [ "$BF_CH" != "1" ]; then
    ask name "Worktree name (blank = auto): "
    CL_WORKTREE=" -w"
    [ -n "$name" ] && CL_WORKTREE=" -w $name"
    [ "$BF_CH" = "3" ] && CL_WORKTREE="$CL_WORKTREE --tmux"
  fi
  STEP=cl_startup
}

# --- 12. STARTUP MODE --------------------------------------------------------
m_cl_startup() {
  header "Claude / Startup"
  sec "STARTUP MODE"
  item "1" "Normal"    "hooks, plugins, CLAUDE.md as usual"
  item "2" "Bare"      "--bare, fastest start"
  item "3" "Safe mode" "--safe-mode, all customizations off"
  note "Bare skips hooks/plugins/CLAUDE.md and needs ANTHROPIC_API_KEY."
  note "Account OAuth will NOT work under --bare."
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_worktree; return 0 ;;
  esac
  CL_STARTUP=""
  [ "$BF_CH" = "2" ] && CL_STARTUP=" --bare"
  [ "$BF_CH" = "3" ] && CL_STARTUP=" --safe-mode"
  STEP=cl_ide
}

# --- 13. IDE -----------------------------------------------------------------
m_cl_ide() {
  header "Claude / IDE"
  sec "IDE INTEGRATION"
  item "1" "None"         "default"
  item "2" "Auto-connect" "--ide, VS Code / JetBrains"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cl_startup; return 0 ;;
  esac
  CL_IDE=""
  [ "$BF_CH" = "2" ] && CL_IDE=" --ide"
  STEP=confirm
}


# =============================================================================
# =============================================================================
#  CODEX FLOW (OpenAI)
# =============================================================================
# =============================================================================
codex_init() {
  AI_KIND="codex"; AI_NAME="Codex"
  CLAUDE_CONFIG_DIR=""
  CX_BASE="codex"; CX_MODEL=""; CX_APPR=""; CX_SEARCH=""; CX_CD=""; CX_PROMPT=""
}

m_cx_session() {
  header "Codex / Session"
  sec "SESSION"
  item "1" "New session" "default"
  item "2" "Resume"      "codex resume, picker"
  item "3" "Resume last" "codex resume --last"
  item "4" "Fork"        "codex fork, picker"
  item "5" "Fork last"   "codex fork --last"
  foot "1-5   [B] back   [Q] quit" "default 1"
  menu_key "12345BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=engine; return 0 ;;
  esac
  CX_BASE="codex"
  case "$BF_CH" in
    2) CX_BASE="codex resume" ;;
    3) CX_BASE="codex resume --last" ;;
    4) CX_BASE="codex fork" ;;
    5) CX_BASE="codex fork --last" ;;
  esac
  CX_NEW="$BF_CH"
  STEP=cx_model
}

# Menu entries come from ai-models.json (engine tag "codex") and are reread on
# every render. Refresh that file from the picker list codex itself caches in
# ~/.codex/models_cache.json (visibility "list") when it ages.
m_cx_model() {
  local i keys="" range=""
  header "Codex / Model"
  load_models codex
  sec "MODEL"
  i=1
  while [ "$i" -le "$MDL_COUNT" ]; do
    eval "item \"\$i\" \"\$MDL_ID_$i\" \"\$MDL_DESC_$i\""
    keys="$keys$i"
    i=$((i + 1))
  done
  item "C" "Custom model id" "-m <id>"
  item "S" "Default"         "no -m flag, uses ~/.codex/config.toml"
  note "Edit ai-models.json next to $BF_SELF to change this list."
  [ -n "$MDL_BAD" ] && note "ai-models.json has a JSON error - fix it or re-download via [U]."
  [ -n "$MDL_MORE" ] && note "Only the first 9 codex entries in ai-models.json are shown."
  [ "$MDL_COUNT" = "0" ] && note "No codex entries in ai-models.json - pick [C] or [S]."
  range="1-$MDL_COUNT   "
  [ "$MDL_COUNT" = "1" ] && range="1   "
  [ "$MDL_COUNT" = "0" ] && range=""
  foot "$range[C] custom   [S] default   [B] back   [Q] quit" "default S"
  menu_key "${keys}CSBQ" "S"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cx_session; return 0 ;;
  esac
  CX_MODEL=""
  case "$BF_CH" in
    S) STEP=cx_appr; return 0 ;;
    C) STEP=cx_custom_model; return 0 ;;
    *) eval "CX_MODEL=\" -m \$MDL_ID_$BF_CH\"" ;;
  esac
  STEP=cx_appr
}

m_cx_custom_model() {
  local id
  note "The menu list lives in ai-models.json next to $BF_SELF."
  printf '\n'
  ask id "Model id: "
  [ -n "$id" ] && CX_MODEL=" -m $id"
  STEP=cx_appr
}

m_cx_appr() {
  header "Codex / Approval"
  sec "APPROVAL AND SANDBOX"
  item "1" "Default"         "codex built-in policy"
  item "2" "YOLO"            "--yolo, no approvals, no sandbox"
  item "3" "Full access"     "-s danger-full-access -a never"
  item "4" "Workspace-write" "-s workspace-write -a on-request"
  item "5" "Read-only"       "-s read-only -a untrusted"
  note "[2] and [3] remove every guardrail. Nothing will ask first."
  foot "1-5   [B] back   [Q] quit" "default 1"
  menu_key "12345BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cx_model; return 0 ;;
  esac
  CX_APPR=""
  case "$BF_CH" in
    2) CX_APPR=" --yolo" ;;
    3) CX_APPR=" -s danger-full-access -a never" ;;
    4) CX_APPR=" -s workspace-write -a on-request" ;;
    5) CX_APPR=" -s read-only -a untrusted" ;;
  esac
  STEP=cx_search
}

m_cx_search() {
  header "Codex / Web search"
  sec "WEB SEARCH"
  item "1" "Off" "default"
  item "2" "On"  "--search"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cx_appr; return 0 ;;
  esac
  CX_SEARCH=""
  [ "$BF_CH" = "2" ] && CX_SEARCH=" --search"
  STEP=cx_cd
}

m_cx_cd() {
  local dir
  header "Codex / Working directory"
  sec "WORKING DIRECTORY"
  item "1" "This folder" "default"
  item "2" "Custom root" "-C <path>"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cx_search; return 0 ;;
  esac
  CX_CD=""
  if [ "$BF_CH" = "2" ]; then
    ask dir "Directory path: "
    [ -n "$dir" ] && CX_CD=" -C \"$dir\""
  fi
  STEP=cx_prompt
}

m_cx_prompt() {
  local txt
  CX_PROMPT=""
  if [ "$CX_NEW" != "1" ]; then STEP=confirm; return 0; fi
  header "Codex / Initial prompt"
  sec "INITIAL PROMPT"
  item "1" "None"             "start interactive"
  item "2" "Provide a prompt" "passed as the first turn"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=cx_cd; return 0 ;;
  esac
  if [ "$BF_CH" = "2" ]; then
    opnote
    ask txt "Prompt: "
    [ -n "$txt" ] && CX_PROMPT=" \"$txt\""
  fi
  STEP=confirm
}


# =============================================================================
# =============================================================================
#  GEMINI FLOW (Google)
# =============================================================================
# =============================================================================
gemini_init() {
  AI_KIND="gemini"; AI_NAME="Gemini"
  CLAUDE_CONFIG_DIR=""
  GM_MODEL=""; GM_APPR=""; GM_SANDBOX=""; GM_SESS=""; GM_WT=""; GM_DIRS=""
  GM_DEBUG=""; GM_PROMPT=""
}

m_gm_model() {
  local id
  header "Gemini / Model"
  sec "MODEL"
  item "1" "Default"         "from config"
  item "2" "Custom model id" "-m <id>"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=engine; return 0 ;;
  esac
  GM_MODEL=""
  if [ "$BF_CH" = "2" ]; then
    note "e.g. gemini-2.5-pro, gemini-2.5-flash"
    printf '\n'
    ask id "Model id: "
    [ -n "$id" ] && GM_MODEL=" -m $id"
  fi
  STEP=gm_appr
}

m_gm_appr() {
  header "Gemini / Approval"
  sec "APPROVAL MODE"
  item "1" "Default"   "prompt for approval"
  item "2" "YOLO"      "--yolo, auto-accept everything"
  item "3" "Auto-edit" "--approval-mode auto_edit"
  item "4" "Plan"      "--approval-mode plan, read-only"
  note "[2] accepts every action without asking."
  foot "1-4   [B] back   [Q] quit" "default 1"
  menu_key "1234BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_model; return 0 ;;
  esac
  GM_APPR=""
  case "$BF_CH" in
    2) GM_APPR=" --yolo" ;;
    3) GM_APPR=" --approval-mode auto_edit" ;;
    4) GM_APPR=" --approval-mode plan" ;;
  esac
  STEP=gm_sandbox
}

m_gm_sandbox() {
  header "Gemini / Sandbox"
  sec "SANDBOX"
  item "1" "Off" "default"
  item "2" "On"  "--sandbox"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_appr; return 0 ;;
  esac
  GM_SANDBOX=""
  [ "$BF_CH" = "2" ] && GM_SANDBOX=" --sandbox"
  STEP=gm_session
}

m_gm_session() {
  local idx
  header "Gemini / Session"
  sec "SESSION"
  item "1" "New session"     "default"
  item "2" "Resume latest"   "--resume latest"
  item "3" "Resume by index" "--resume <n>"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_sandbox; return 0 ;;
  esac
  GM_SESS=""
  [ "$BF_CH" = "2" ] && GM_SESS=" --resume latest"
  if [ "$BF_CH" = "3" ]; then
    ask idx "Session index number: "
    [ -n "$idx" ] && GM_SESS=" --resume $idx"
  fi
  STEP=gm_worktree
}

m_gm_worktree() {
  local name
  header "Gemini / Worktree"
  sec "GIT WORKTREE"
  item "1" "None"         "default"
  item "2" "New worktree" "-w, blank name = auto"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_session; return 0 ;;
  esac
  GM_WT=""
  if [ "$BF_CH" = "2" ]; then
    ask name "Worktree name (blank = auto): "
    GM_WT=" -w"
    [ -n "$name" ] && GM_WT=" -w $name"
  fi
  STEP=gm_dirs
}

m_gm_dirs() {
  local list
  header "Gemini / Directories"
  sec "ADDITIONAL WORKING DIRECTORIES"
  item "1" "None"         "default"
  item "2" "Include dirs" "--include-directories"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_worktree; return 0 ;;
  esac
  GM_DIRS=""
  if [ "$BF_CH" = "2" ]; then
    ask list "Directories (comma-separated): "
    [ -n "$list" ] && GM_DIRS=" --include-directories $list"
  fi
  STEP=gm_debug
}

m_gm_debug() {
  header "Gemini / Logging"
  sec "DEBUG"
  item "1" "Off" "default"
  item "2" "On"  "--debug"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_dirs; return 0 ;;
  esac
  GM_DEBUG=""
  [ "$BF_CH" = "2" ] && GM_DEBUG=" --debug"
  STEP=gm_prompt
}

m_gm_prompt() {
  local flag txt
  header "Gemini / Initial prompt"
  sec "INITIAL PROMPT"
  item "1" "None"        "start interactive"
  item "2" "Interactive" "-i <prompt>"
  item "3" "Headless"    "-p <prompt>, non-interactive"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=gm_debug; return 0 ;;
  esac
  GM_PROMPT=""
  if [ "$BF_CH" != "1" ]; then
    flag="-i"
    [ "$BF_CH" = "3" ] && flag="-p"
    opnote
    ask txt "Prompt: "
    [ -n "$txt" ] && GM_PROMPT=" $flag \"$txt\""
  fi
  STEP=confirm
}


# =============================================================================
# =============================================================================
#  ANTIGRAVITY FLOW (Google - agy terminal agent)
# =============================================================================
# =============================================================================
agy_init() {
  AI_KIND="agy"; AI_NAME="Antigravity"
  CLAUDE_CONFIG_DIR=""
  AG_SESS=""; AG_PERM=""; AG_SB=""; AG_DIR=""; AG_PROMPT=""
}

m_ag_session() {
  local conv
  header "Antigravity / Session"
  sec "SESSION"
  item "1" "New conversation"     "default"
  item "2" "Continue most recent" "-c"
  item "3" "Resume by id"         "--conversation <id>"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=engine; return 0 ;;
  esac
  AG_SESS=""
  [ "$BF_CH" = "2" ] && AG_SESS=" -c"
  if [ "$BF_CH" = "3" ]; then
    ask conv "Conversation ID: "
    [ -n "$conv" ] && AG_SESS=" --conversation $conv"
  fi
  STEP=ag_perm
}

m_ag_perm() {
  header "Antigravity / Permissions"
  sec "PERMISSIONS"
  item "1" "Default" "prompt for each tool action"
  item "2" "YOLO"    "--dangerously-skip-permissions"
  note "[2] auto-approves every tool permission."
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=ag_session; return 0 ;;
  esac
  AG_PERM=""
  [ "$BF_CH" = "2" ] && AG_PERM=" --dangerously-skip-permissions"
  STEP=ag_sandbox
}

m_ag_sandbox() {
  header "Antigravity / Sandbox"
  sec "SANDBOX"
  item "1" "Off" "default"
  item "2" "On"  "--sandbox, terminal restrictions"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=ag_perm; return 0 ;;
  esac
  AG_SB=""
  [ "$BF_CH" = "2" ] && AG_SB=" --sandbox"
  STEP=ag_dirs
}

m_ag_dirs() {
  local dir
  header "Antigravity / Directories"
  sec "ADDITIONAL WORKING DIRECTORIES"
  item "1" "None"          "default"
  item "2" "Add directory" "--add-dir <path>"
  foot "1 2   [B] back   [Q] quit" "default 1"
  menu_key "12BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=ag_sandbox; return 0 ;;
  esac
  AG_DIR=""
  if [ "$BF_CH" = "2" ]; then
    ask dir "Directory path: "
    [ -n "$dir" ] && AG_DIR=" --add-dir \"$dir\""
  fi
  STEP=ag_prompt
}

m_ag_prompt() {
  local flag txt
  header "Antigravity / Initial prompt"
  sec "INITIAL PROMPT"
  item "1" "None"        "start interactive"
  item "2" "Interactive" "-i <prompt>"
  item "3" "Headless"    "-p <prompt>, print once"
  foot "1 2 3   [B] back   [Q] quit" "default 1"
  menu_key "123BQ" "1"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    B) STEP=ag_dirs; return 0 ;;
  esac
  AG_PROMPT=""
  if [ "$BF_CH" != "1" ]; then
    flag="-i"
    [ "$BF_CH" = "3" ] && flag="-p"
    opnote
    ask txt "Prompt: "
    [ -n "$txt" ] && AG_PROMPT=" $flag \"$txt\""
  fi
  STEP=confirm
}


# =============================================================================
#  COMMAND BUILDERS
#  Every flow stores its choices in named variables and rebuilds CMD from
#  scratch on each render, so [B] back never double-appends a flag.
# =============================================================================
build() {
  # A hand-edited command is authoritative; never regenerate over the top of it.
  [ -n "$AI_EDITED" ] && return 0
  case "$AI_KIND" in
    claude)
      CMD="claude --dangerously-skip-permissions"
      [ -n "$PERM_MODE" ] && CMD="claude --permission-mode $PERM_MODE"
      [ -n "$MODEL_FLAG" ] && CMD="$CMD $MODEL_FLAG"
      [ -n "$EFFORT_FLAG" ] && CMD="$CMD $EFFORT_FLAG"
      CMD="$CMD$CL_SESSION$CL_VERBOSE$CL_ADDDIR$CL_SYSPROMPT$CL_MCP"
      CMD="$CMD$CL_TOOLS$CL_CHROME$CL_WORKTREE$CL_STARTUP$CL_IDE$BF_EXTRA"
      ;;
    codex)  CMD="$CX_BASE$CX_MODEL$CX_APPR$CX_SEARCH$CX_CD$BF_EXTRA$CX_PROMPT" ;;
    gemini) CMD="gemini$GM_MODEL$GM_APPR$GM_SANDBOX$GM_SESS$GM_WT$GM_DIRS$GM_DEBUG$BF_EXTRA$GM_PROMPT" ;;
    agy)    CMD="agy$AG_SESS$AG_PERM$AG_SB$AG_DIR$BF_EXTRA$AG_PROMPT" ;;
  esac
  return 0
}


# =============================================================================
#  SHARED: CONFIRM / EDIT / CHDIR / RUN
# =============================================================================
m_confirm() {
  header "Confirm"
  sec "READY"
  item "Y" "Launch"       "run the command above"
  item "E" "Edit command" "hand-edit before running"
  item "D" "Change dir"   "pick a different working directory"
  item "R" "Engine menu"  "start over"
  foot "[Y] launch  [E] edit  [D] dir  [R] restart  [Q] quit" "timeout quits"
  menu_key "YEDRQ" "Q"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit ;;
    Y) STEP=run ;;
    E) STEP=edit ;;
    D) STEP=chdir ;;
    R) STEP=engine ;;
    *) unreachable ;;
  esac
}

m_chdir() {
  local newroot
  header "Working directory"
  sec "CURRENT"
  kv "Working" "$REPO_ROOT"
  kv "Script " "$SCRIPT_DIR"
  sec "NEW"
  note "Enter a path, S for the script folder, or blank to keep the current one."
  printf '\n'
  ask newroot "Working directory: "
  if [ -z "$newroot" ]; then STEP=confirm; return 0; fi
  case "$newroot" in
    S|s) newroot="$SCRIPT_DIR" ;;
    "~"/*) newroot="$HOME/${newroot#\~/}" ;;
  esac
  if [ ! -d "$newroot" ]; then
    err "not a directory: $newroot - check the path and try again"
    hold
    STEP=confirm
    return 0
  fi
  REPO_ROOT="$(cd "$newroot" && pwd -P)"
  STEP=confirm
}

m_edit() {
  local newcmd
  header "Edit command"
  sec "CURRENT COMMAND"
  printf '\n   %s\n\n' "$CMD"
  note "Blank entry keeps the command unchanged."
  printf '\n'
  ask newcmd "Command: "
  # Only a real edit freezes the command; a blank entry leaves the flow's own
  # rebuild in charge.
  if [ -n "$newcmd" ]; then
    CMD="$newcmd"
    AI_EDITED=1
  fi
  header "Edit command"
  sec "UPDATED"
  foot "[Y] launch   [N] back" "timeout = back"
  menu_key "YN" "N"
  [ -n "$BF_STOP" ] && return 0
  if [ "$BF_CH" = "Y" ]; then STEP=run; else STEP=confirm; fi
}

run_cmd() {
  [ -z "$BF_NONINTERACTIVE" ] && header "Launching"
  if [ -z "$CMD" ]; then
    err "no command was built; pick an engine first"
    BF_EXIT=2; return 0
  fi
  info "Starting $AI_NAME in $REPO_ROOT"
  printf '\n'
  if ! cd "$REPO_ROOT" 2>/dev/null; then
    err "cannot enter working directory $REPO_ROOT - it may have been deleted or renamed"
    BF_EXIT=5; return 0
  fi
  [ -n "$CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR
  # eval on purpose: it is the only form that runs a command string carrying
  # quotes and operators. See opnote for the tradeoff.
  eval "$CMD"
  BF_EXIT=$?
  printf '\n'
  info "$AI_NAME session ended with exit code $BF_EXIT"
  return 0
}


# =============================================================================
#  AUTH SETUP (Claude - first-time login for both accounts)
# =============================================================================
m_auth_setup() {
  header "Claude / Auth setup"
  sec "ACCOUNT AUTH"
  note "Logs in two accounts. Run once. After this, pick [1] or [2]."
  rule

  sec "ACCOUNT 1 - LOG IN VIA YOUR DEFAULT BROWSER"
  note "Make sure Account 1 is logged in on claude.ai there."
  note "A browser will open for OAuth."
  foot "[Y] continue   [S] skip   [Q] quit" "timeout skips"
  menu_key "YSQ" "S"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    Y) printf '\n'
       CLAUDE_CONFIG_DIR="$HOME/.claude-acc1" claude auth login
       printf '\n'
       sec "ACCOUNT 1 STATUS"
       CLAUDE_CONFIG_DIR="$HOME/.claude-acc1" claude auth status ;;
  esac

  header "Claude / Auth setup"
  sec "ACCOUNT 2 - LOG IN VIA A SECOND BROWSER"
  note "Make sure Account 2 is logged in on claude.ai in that browser."
  note "If the wrong browser opens, copy the URL into the other one."
  foot "[Y] continue   [S] skip   [Q] quit" "timeout skips"
  menu_key "YSQ" "S"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    Q) STEP=quit; return 0 ;;
    Y) printf '\n'
       CLAUDE_CONFIG_DIR="$HOME/.claude-acc2" claude auth login
       printf '\n'
       sec "ACCOUNT 2 STATUS"
       CLAUDE_CONFIG_DIR="$HOME/.claude-acc2" claude auth status ;;
  esac

  printf '\n'
  ok "Auth setup finished. Returning to the account menu."
  CLAUDE_CONFIG_DIR=""
  hold
  STEP=cl_account
}


# =============================================================================
#  ENV FIX (put this script's folder on PATH permanently)
#  The Windows build also sets CLAUDE_CODE_GIT_BASH_PATH; there is no such
#  requirement here, so this only touches PATH, and only through a guarded block
#  appended to the login shell's rc file.
# =============================================================================
shell_rc() {
  case "${SHELL:-}" in
    */zsh)  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    */bash) if [ -f "$HOME/.bash_profile" ]; then printf '%s\n' "$HOME/.bash_profile"
            else printf '%s\n' "$HOME/.bashrc"; fi ;;
    */fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *)      printf '%s\n' "$HOME/.profile" ;;
  esac
}

m_env_fix() {
  local rc
  rc="$(shell_rc)"
  header "Fix environment"
  sec "WHAT THIS CHANGES"
  note "1. Appends this script's folder to PATH in your shell rc file."
  note "2. Makes sure $BF_SELF itself is executable."
  printf '\n'
  kv "Folder" "$SCRIPT_DIR"
  kv "RC    " "$rc"
  if [ -z "$BF_ASSUME_YES" ]; then
    foot "[Y] apply   [N] cancel" "timeout = no"
    menu_key "YN" "N"
    [ -n "$BF_STOP" ] && return 0
    if [ "$BF_CH" != "Y" ]; then
      printf '\n'
      info "Cancelled. Nothing was changed."
      if [ -n "$BF_FIXENV" ]; then STEP=quit; else hold; STEP=engine; fi
      return 0
    fi
  fi
  env_fix_go
  if [ -n "$BF_FIXENV" ]; then STEP=quit; else hold; STEP=engine; fi
}

env_fix_go() {
  local rc line
  rc="$(shell_rc)"
  printf '\n'
  sec "APPLYING"

  chmod +x "$SCRIPT_DIR/$BF_SELF" 2>/dev/null \
    && ok "executable bit set on $BF_SELF" \
    || warn "could not chmod +x $SCRIPT_DIR/$BF_SELF - run chmod by hand"

  case ":${PATH}:" in
    *":$SCRIPT_DIR:"*) info "already on PATH in this shell" ;;
  esac

  if [ -f "$rc" ] && grep -Fq "# added by ai.sh" "$rc" && grep -Fq "$SCRIPT_DIR" "$rc"; then
    ok "already in $rc"
  else
    case "$rc" in
      *config.fish) line="set -gx PATH \$PATH \"$SCRIPT_DIR\"" ;;
      *)            line="export PATH=\"\$PATH:$SCRIPT_DIR\"" ;;
    esac
    mkdir -p "$(dirname "$rc")" 2>/dev/null
    if { printf '\n# added by ai.sh\n%s\n' "$line" >>"$rc"; } 2>/dev/null; then
      ok "added to $rc"
    else
      err "could not write $rc - add this line by hand: $line"
      return 0
    fi
  fi
  printf '\n'
  ok "Done. Open a new terminal (or source $rc) for PATH changes to take effect."
  return 0
}


# =============================================================================
#  JSON HELPERS
#  macOS ships neither jq nor a guaranteed python3, so every JSON path degrades:
#  python3 first, jq second, and for the menu list a last-resort awk scan that
#  keeps the menus working when neither is installed.
# =============================================================================
have() { command -v "$1" >/dev/null 2>&1; }

json_tool() {
  if have python3; then printf 'python3\n'
  elif have jq;    then printf 'jq\n'
  else printf 'none\n'; fi
}

# Reads the Anthropic API key the same way ai.bat does: the environment first,
# then the CLI's own config file. Read at runtime, never stored.
anthropic_key() {
  local cfg
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    printf '%s\n' "$ANTHROPIC_API_KEY"
    return 0
  fi
  for cfg in "$HOME/Library/Application Support/claude/config.json" \
             "$HOME/.config/claude/config.json" \
             "$HOME/.claude/config.json"; do
    [ -f "$cfg" ] || continue
    case "$(json_tool)" in
      python3) python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("apiKey","") or "")
except Exception:
    pass' "$cfg" 2>/dev/null && return 0 ;;
      jq) jq -r '.apiKey // empty' "$cfg" 2>/dev/null && return 0 ;;
      *)  sed -n 's/.*"apiKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" 2>/dev/null && return 0 ;;
    esac
  done
  return 0
}


# =============================================================================
#  MODEL LIST FETCH (Claude)
#  Shown by [C] custom model, so you can see what the key actually allows.
# =============================================================================
fetch_models() {
  local key resp
  key="$(anthropic_key | head -1)"
  if [ -z "$key" ]; then
    printf '   No ANTHROPIC_API_KEY found - cannot query the live list.\n\n'
    printf '   Aliases:  opus, sonnet, haiku, opusplan\n'
    printf '   The menu list lives in ai-models.json next to %s.\n' "$BF_SELF"
    return 0
  fi
  if ! have curl; then
    printf '   curl not found - cannot query the live list.\n'
    return 0
  fi
  resp="$(curl -fsS --max-time 10 \
            -H "x-api-key: $key" \
            -H "anthropic-version: 2023-06-01" \
            'https://api.anthropic.com/v1/models?limit=100' 2>&1)" || {
    printf '   API call failed: %s\n\n' "$(printf '%s' "$resp" | head -1)"
    printf '   Aliases:  opus, sonnet, haiku, opusplan\n'
    return 0
  }
  printf '   Models available on your account:\n\n'
  case "$(json_tool)" in
    python3) printf '%s' "$resp" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin).get("data", [])
except Exception:
    sys.exit(0)
for m in sorted(d, key=lambda x: x.get("id","")):
    print("     " + str(m.get("id","")).ljust(45) + str(m.get("display_name") or ""))' ;;
    jq) printf '%s' "$resp" | jq -r '.data | sort_by(.id)[] | "     " + (.id + "                                             ")[0:45] + (.display_name // "")' ;;
    *)  printf '%s' "$resp" | tr ',' '\n' | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/     \1/p' | sort ;;
  esac
  printf '\n   Aliases (always available):\n'
  printf '     opus, sonnet, haiku, opusplan\n'
  return 0
}


# =============================================================================
#  MODEL MENU LIST (external, editable, updatable)
#  ai-models.json next to the script feeds the Claude and Codex model menus:
#      { "claude": [ { "id": "...", "desc": "..." } ], "codex": [ ... ] }
#  Array order is menu order. The JSON is converted to pipe-delimited lines in
#  MDL_LINES; the conversion reruns only when the file's stamp (mtime+size)
#  changes, so menus render instantly and a mid-run edit still shows up. Menu
#  keys are single digits, so the first 9 entries per engine are shown; the key
#  hints in the calling menus use the same count.
# =============================================================================
# $1 = engine tag. Fills MDL_ID_1..9 / MDL_DESC_1..9 and MDL_COUNT; sets
# MDL_MORE when entries past the ninth were dropped.
load_models() {
  local engine="$1" stamp i id desc line
  MDL_COUNT=0
  MDL_MORE=""
  i=1
  while [ "$i" -le 9 ]; do
    eval "MDL_ID_$i=''; MDL_DESC_$i=''"
    i=$((i + 1))
  done
  [ -f "$MODELS_FILE" ] || write_default_models
  [ -f "$MODELS_FILE" ] || return 0
  stamp="$(file_stamp "$MODELS_FILE")"
  [ "$stamp" != "$MDL_STAMP" ] && parse_models "$stamp"
  [ -f "$MDL_LINES" ] || return 0
  while IFS='|' read -r eng id desc; do
    [ "$eng" = "$engine" ] || continue
    [ -n "$id" ] || continue
    if [ "$MDL_COUNT" -lt 9 ]; then
      MDL_COUNT=$((MDL_COUNT + 1))
      eval "MDL_ID_$MDL_COUNT=\$id; MDL_DESC_$MDL_COUNT=\$desc"
    else
      MDL_MORE=1
    fi
  done <"$MDL_LINES"
  return 0
}

file_stamp() {
  # BSD stat on macOS, GNU stat elsewhere; either way mtime + size.
  stat -f '%m %z' "$1" 2>/dev/null || stat -c '%Y %s' "$1" 2>/dev/null || printf '?\n'
}

# JSON -> lines conversion. Ids and descriptions are allowlist-filtered because
# both end up inside CMD, which run_cmd hands to eval. A failed parse keeps the
# previous lines file so the menus keep working; the stamp is recorded either
# way so a broken file is not re-parsed on every render.
parse_models() {
  local raw
  MDL_BAD=""
  MDL_STAMP="$1"
  raw=""
  case "$(json_tool)" in
    python3) raw="$(python3 -c 'import json,sys
try:
    m = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for eng in ("claude", "codex"):
    for e in (m.get(eng) or []):
        print("%s|%s|%s" % (eng, e.get("id",""), e.get("desc","")))' "$MODELS_FILE" 2>/dev/null)" || MDL_BAD=1 ;;
    jq) raw="$(jq -r '["claude","codex"][] as $e | (.[$e] // [])[] | "\($e)|\(.id // "")|\(.desc // "")"' "$MODELS_FILE" 2>/dev/null)" || MDL_BAD=1 ;;
    *)  # Last resort: neither python3 nor jq. Scan the file for id/desc pairs
        # inside each engine array. Good enough for the machine-generated shape
        # this file has; [U] and hand edits keep that shape.
        raw="$(awk '
          /"claude"[[:space:]]*:/ { eng = "claude" }
          /"codex"[[:space:]]*:/  { eng = "codex" }
          {
            line = $0
            if (match(line, /"id"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
              s = substr(line, RSTART, RLENGTH); sub(/.*"[[:space:]]*:[[:space:]]*"/, "", s); sub(/"$/, "", s); id = s
            }
            if (match(line, /"desc"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
              s = substr(line, RSTART, RLENGTH); sub(/.*"[[:space:]]*:[[:space:]]*"/, "", s); sub(/"$/, "", s); d = s
            }
            if (line ~ /}/ && id != "" && eng != "") { print eng "|" id "|" d; id = ""; d = "" }
          }' "$MODELS_FILE" 2>/dev/null)"
        [ -n "$raw" ] || MDL_BAD=1 ;;
  esac
  [ -n "$MDL_BAD" ] && return 0
  [ -n "$MDL_LINES" ] || MDL_LINES="$(mktemp "${TMPDIR:-/tmp}/ai-sh-models.XXXXXX")"
  printf '%s\n' "$raw" | awk -F'|' 'NF>=2 {
      id = $2; d = $3
      gsub(/[^A-Za-z0-9._@:\/-]/, "", id)
      gsub(/[^A-Za-z0-9 ._,+\/@:-]/, "", d)
      if (id != "") print $1 "|" id "|" d
    }' >"$MDL_LINES" 2>/dev/null || MDL_BAD=1
  return 0
}

# First run of a standalone copy: materialize the built-in defaults so there is
# always a file to edit. Keep this block in sync with the ai-models.json shipped
# in the repo.
write_default_models() {
  cat >"$MODELS_FILE" <<'EOF' 2>/dev/null
{
  "comment": "Model menus for ai.sh / ai.bat. Order = menu order; the first 9 per engine are shown. Edit by hand or run: ai.sh --update-models",
  "claude": [
    { "id": "claude-opus-5", "desc": "Opus 5 - newest Opus" },
    { "id": "claude-fable-5", "desc": "Fable 5 - most capable tier" },
    { "id": "claude-opus-4-8", "desc": "Opus 4.8 - adaptive thinking" },
    { "id": "claude-opus-4-7", "desc": "Opus 4.7 - adaptive thinking" },
    { "id": "claude-sonnet-5", "desc": "Sonnet 5 - near-Opus, faster" },
    { "id": "claude-sonnet-4-6", "desc": "Sonnet 4.6 - extended + adaptive" },
    { "id": "claude-haiku-4-5", "desc": "Haiku 4.5 - fast, cost-effective" },
    { "id": "claude-opus-4-6", "desc": "Opus 4.6 - extended + adaptive" }
  ],
  "codex": [
    { "id": "gpt-5.6-sol", "desc": "latest frontier agentic coding model" },
    { "id": "gpt-5.6-terra", "desc": "balanced, for everyday work" },
    { "id": "gpt-5.6-luna", "desc": "fast and affordable" },
    { "id": "gpt-5.5", "desc": "complex coding, research, real work" },
    { "id": "gpt-5.4", "desc": "strong for everyday coding" },
    { "id": "gpt-5.4-mini", "desc": "small, fast, cost-efficient" }
  ]
}
EOF
  if [ ! -f "$MODELS_FILE" ]; then
    warn "could not create $MODELS_FILE - model menus will only offer custom and skip"
    return 0
  fi
  info "created $MODELS_FILE with the default model lists"
  return 0
}


# =============================================================================
#  MODEL LIST UPDATER
#  Fetches ai-models.json from AI_BAT_MODELS_URL. The download is validated as
#  JSON and written to a temp name first, swapped in only on success, so a
#  failed or garbled fetch never destroys the local file. The fetch itself is
#  bounded at 10 seconds.
# =============================================================================
m_update_models() {
  header "Update model lists"
  sec "SOURCE"
  kv "URL " "$AI_BAT_MODELS_URL"
  kv "File" "$MODELS_FILE"
  sec "UPDATE MODE"
  item "Y" "From URL"     "download the published list from GitHub"
  item "L" "Live rebuild" "Anthropic API or models.dev + codex cache"
  item "N" "Cancel"       "keep the current file"
  printf '\n'
  note "Either mode replaces the local file, including hand edits."
  foot "[Y] from url   [L] live   [N] cancel" "timeout = no"
  menu_key "YLN" "N"
  [ -n "$BF_STOP" ] && return 0
  case "$BF_CH" in
    L) printf '\n'; sec "REBUILDING FROM LIVE SOURCES"; models_refresh_go; hold ;;
    Y) printf '\n'; sec "FETCHING"; models_update_go; hold ;;
  esac
  STEP=engine
}

# AI_BAT_AUTO_UPDATE: refresh at launch, but only when the local list is at
# least a day old. A successful "already up to date" fetch touches the file's
# mtime so the daily gate does not re-fire on every launch.
auto_update_check() {
  if [ -f "$MODELS_FILE" ]; then
    find "$MODELS_FILE" -mtime +0 2>/dev/null | grep -q . || return 0
  fi
  info "model list is stale - refreshing (AI_BAT_AUTO_UPDATE is set)"
  models_update_go
}

json_valid() {
  case "$(json_tool)" in
    python3) python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1 ;;
    jq)      jq -e . "$1" >/dev/null 2>&1 ;;
    *)       grep -q '"claude"' "$1" 2>/dev/null && grep -q '"codex"' "$1" 2>/dev/null ;;
  esac
}

# Shared fetch. Prints its own status lines and leaves MDL_UPD_RC 0/1.
models_update_go() {
  local tmp
  MDL_UPD_RC=0
  if ! have curl; then
    err "curl not found - cannot download the model list"
    MDL_UPD_RC=1
    return 0
  fi
  printf '   Fetching %s\n' "$AI_BAT_MODELS_URL"
  tmp="$MODELS_FILE.new"
  if ! curl -fsSL --max-time 10 -o "$tmp" "$AI_BAT_MODELS_URL" 2>/dev/null; then
    rm -f "$tmp"
    printf '   Update failed: could not download the list.\n'
    MDL_UPD_RC=1
    err "model list update failed - check the URL above and your connection, then retry"
    return 0
  fi
  if ! json_valid "$tmp"; then
    rm -f "$tmp"
    printf '   Update failed: the download is not valid JSON.\n'
    MDL_UPD_RC=1
    err "model list update failed - the server returned something that is not the model list"
    return 0
  fi
  if [ -f "$MODELS_FILE" ] && cmp -s "$tmp" "$MODELS_FILE"; then
    rm -f "$tmp"
    touch "$MODELS_FILE"
    printf '   Already up to date.\n'
  else
    mv -f "$tmp" "$MODELS_FILE"
    printf '   Updated %s\n' "$MODELS_FILE"
  fi
  MDL_STAMP=""
  return 0
}

# Live rebuild. Claude comes from the Anthropic API when a key is available
# (ANTHROPIC_API_KEY or apiKey in the CLI's config.json - same sources as
# fetch_models), else from models.dev, a public no-auth model database that uses
# the vendors' native ids. Codex comes from the picker cache codex itself
# maintains in ~/.codex/models_cache.json - those are the only slugs "codex -m"
# accepts, so no website beats it. Any section whose sources are unreachable
# keeps its current entries; if nothing is reachable the file is left untouched
# and the exit code is 1. Output is deterministic (no timestamps), so re-running
# without upstream changes is a no-op commit.
models_refresh_go() {
  MDL_UPD_RC=0
  if ! have python3; then
    printf '   Live rebuild needs python3 (not found).\n'
    err "live model refresh needs python3 - use --update-models to fetch the published list instead"
    MDL_UPD_RC=1
    return 0
  fi
  ANTHROPIC_KEY_RESOLVED="$(anthropic_key | head -1)" \
  MODELS_FILE="$MODELS_FILE" \
  python3 - <<'PY'
import json, os, sys, urllib.request

dst = os.environ["MODELS_FILE"]
key = os.environ.get("ANTHROPIC_KEY_RESOLVED", "")

def get(url, headers=None, timeout=15):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))

old = None
try:
    with open(dst) as f:
        old = json.load(f)
except Exception:
    old = None

claude, src_c = [], ""
if key:
    try:
        resp = get("https://api.anthropic.com/v1/models?limit=100",
                   {"x-api-key": key, "anthropic-version": "2023-06-01"}, 10)
        claude = [{"id": m["id"],
                   "desc": "%s - %s" % (m.get("display_name", ""), str(m.get("created_at", ""))[:10])}
                  for m in resp.get("data", [])[:9]]
        src_c = "Anthropic API"
    except Exception:
        claude = []
if not claude:
    try:
        md = get("https://models.dev/api.json", None, 15)
        models = (md.get("anthropic") or {}).get("models") or {}
        ordered = sorted(models.items(), key=lambda kv: str(kv[1].get("release_date", "")), reverse=True)[:9]
        claude = [{"id": k, "desc": "%s - %s" % (v.get("name", ""), v.get("release_date", ""))}
                  for k, v in ordered]
        src_c = "models.dev"
    except Exception:
        claude = []
if not claude and old and old.get("claude"):
    claude = old["claude"]
    src_c = "kept existing - fetch failed"

codex, src_x = [], ""
cc = os.path.expanduser("~/.codex/models_cache.json")
if os.path.exists(cc):
    try:
        with open(cc) as f:
            cj = json.load(f)
        listed = [m for m in cj.get("models", []) if m.get("visibility") == "list"]
        listed.sort(key=lambda m: m.get("priority", 0))
        codex = [{"id": m.get("slug", ""), "desc": m.get("description", "")} for m in listed[:9]]
        src_x = "codex cache"
    except Exception:
        codex = []
if not codex and old and old.get("codex"):
    codex = old["codex"]
    src_x = "kept existing - no codex cache"

if not claude and not codex:
    print("   Nothing fetched - file left unchanged.")
    sys.exit(1)

doc = {"comment": "Model menus for ai.sh / ai.bat. Rebuilt by --refresh-models. "
                  "Order = menu order; the first 9 per engine are shown.",
       "claude": claude, "codex": codex}
tmp = dst + ".new"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=4)
    f.write("\n")
with open(tmp) as f:
    json.load(f)
os.replace(tmp, dst)
print("   claude: %d models - source: %s" % (len(claude), src_c))
print("   codex:  %d models - source: %s" % (len(codex), src_x))
print("   Wrote %s" % dst)
PY
  if [ $? -ne 0 ]; then
    MDL_UPD_RC=1
    err "live model refresh failed - no source reachable; the local file was not changed"
  fi
  MDL_STAMP=""
  return 0
}


# =============================================================================
#  CONTEXT, ARGUMENTS, ROOT DISCOVERY
# =============================================================================
detect_context() {
  # NO_COLOR: present and non-empty disables color whatever its value.
  [ -n "${NO_COLOR:-}" ] && BF_NOCOLOR=1
  [ "${TERM:-}" = "dumb" ] && BF_NOCOLOR=1

  [ -n "${CI:-}" ] && BF_NONINTERACTIVE=1
  [ -n "${GITHUB_ACTIONS:-}" ] && BF_NONINTERACTIVE=1
  [ -n "${TF_BUILD:-}" ] && BF_NONINTERACTIVE=1
  [ -n "${NO_INPUT:-}" ] && BF_NONINTERACTIVE=1

  # Without a terminal on stdin there is no bounded key read, so never enter the
  # menu.
  [ -t 0 ] || BF_NONINTERACTIVE=1

  [ -z "$BF_NOCOLOR" ] && BF_COLOR=1
  [ -n "$BF_NONINTERACTIVE" ] && BF_COLOR=""
  [ -n "${FORCE_COLOR:-}" ] && [ -z "$BF_NOCOLOR" ] && BF_COLOR=1
  return 0
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h|-\?) usage; BF_STOP=1; return 0 ;;
      --version) printf '%s %s\n' "$BF_NAME" "$BF_VERSION"; BF_STOP=1; return 0 ;;
      --no-color) BF_NOCOLOR=1; BF_COLOR=""; shift ;;
      --no-input) BF_NONINTERACTIVE=1; BF_COLOR=""; shift ;;
      --yes) BF_ASSUME_YES=1; shift ;;
      --print-cmd) BF_PRINT_ONLY=1; shift ;;
      --fix-env) BF_FIXENV=1; BF_ASSUME_YES=1; shift ;;
      --update-models) BF_UPDATE=1; shift ;;
      --refresh-models) BF_REFRESH=1; shift ;;
      --ai)
        [ $# -ge 2 ] || { err "--ai needs a value: claude, codex, gemini or antigravity"; BF_EXIT=2; return 0; }
        case "$2" in
          claude)      claude_init ;;
          codex)       codex_init ;;
          gemini)      gemini_init ;;
          antigravity) agy_init ;;
          *) err "unknown engine '$2'; expected claude, codex, gemini or antigravity"; BF_EXIT=2; return 0 ;;
        esac
        shift 2 ;;
      --dir)
        [ $# -ge 2 ] || { err "--dir needs a directory path"; BF_EXIT=2; return 0; }
        [ -d "$2" ] || { err "not a directory: $2"; BF_EXIT=5; return 0; }
        AI_BAT_ROOT="$2"; shift 2 ;;
      --model)
        [ $# -ge 2 ] || { err "--model needs a value; try --help"; BF_EXIT=2; return 0; }
        MODEL_FLAG="--model $2"; CX_MODEL=" -m $2"; GM_MODEL=" -m $2"; shift 2 ;;
      --effort)
        [ $# -ge 2 ] || { err "--effort needs a value; try --help"; BF_EXIT=2; return 0; }
        EFFORT_FLAG="--effort $2"; shift 2 ;;
      --perm)
        [ $# -ge 2 ] || { err "--perm needs a value; try --help"; BF_EXIT=2; return 0; }
        PERM_MODE="$2"; shift 2 ;;
      --account)
        [ $# -ge 2 ] || { err "--account needs a value; try --help"; BF_EXIT=2; return 0; }
        [ "$2" = "1" ] && CLAUDE_CONFIG_DIR="$HOME/.claude-acc1"
        [ "$2" = "2" ] && CLAUDE_CONFIG_DIR="$HOME/.claude-acc2"
        shift 2 ;;
      --extra)
        [ $# -ge 2 ] || { err "--extra needs a value; try --help"; BF_EXIT=2; return 0; }
        BF_EXTRA="$BF_EXTRA $2"; shift 2 ;;
      *) err "unknown argument '$1'; try --help"; BF_EXIT=2; return 0 ;;
    esac
  done
  return 0
}

# -----------------------------------------------------------------------------
#  WORKING DIRECTORY
#  This script is meant to be vendored into a bigger project as a submodule or a
#  plain copy. The agent should run at the top of that project, not in this
#  folder, so walk up and use the outermost directory that owns a .git entry.
#  Override with AI_BAT_ROOT, --dir, or [D] on the confirm screen.
# -----------------------------------------------------------------------------
resolve_root() {
  local scan parent walk=0
  REPO_ROOT=""
  if [ -n "${AI_BAT_ROOT:-}" ] && [ -d "$AI_BAT_ROOT" ]; then
    REPO_ROOT="$(cd "$AI_BAT_ROOT" && pwd -P)"
    return 0
  fi
  # .git is a directory in a normal clone and a file in a submodule or worktree,
  # so a plain existence test covers both. The counter is a backstop against a
  # pathological path that never reaches the filesystem root.
  scan="$SCRIPT_DIR"
  while [ -n "$scan" ] && [ "$walk" -lt "$BF_ROOT_CAP" ]; do
    walk=$((walk + 1))
    [ -e "$scan/.git" ] && REPO_ROOT="$scan"
    parent="$(dirname "$scan")"
    [ "$parent" = "$scan" ] && break
    scan="$parent"
  done
  [ -n "$REPO_ROOT" ] || REPO_ROOT="$SCRIPT_DIR"
  return 0
}


# =============================================================================
#  USAGE
#  Goes to stdout and exits 0.
# =============================================================================
usage() {
  cat <<EOF
$BF_NAME $BF_VERSION

Launches Claude, Codex, Gemini or Antigravity with the flags you pick.

Usage: $BF_SELF [options]

  With no options it opens the interactive menu.
  With --ai it builds and runs the command directly, no menu.

Options:
  --ai <claude|codex|gemini|antigravity>   engine to launch
  --account <1|2>            Claude config profile to use
  --model <id>               model id passed to the engine
  --effort <low|medium|high|xhigh|max>     Claude effort level
  --perm <mode>              Claude permission mode
  --extra <text>             extra flags appended verbatim
  --dir <path>               working directory to run in
  --print-cmd                print the assembled command, do not run it
  --fix-env                  add this folder to PATH permanently, then exit
  --update-models            download the model list, then exit
  --refresh-models           rebuild the list from live sources, then exit
  --yes                      skip confirmation prompts
  --no-color                 disable colored output
  --no-input                 never prompt; fail instead
  --version                  print version and exit
  -h, --help                 print this help and exit

Environment:
  AI_BAT_ROOT         working directory override
  AI_BAT_ACCENT       SGR params for the accent color, default 38;5;208
  AI_BAT_MODELS_URL   source URL for model list updates
  AI_BAT_AUTO_UPDATE  refresh the model list at launch, at most once a day
  AI_BAT_TIMEOUT      seconds a menu waits before taking its default
  NO_COLOR            disables color when set and non-empty
  FORCE_COLOR         re-enables color unless NO_COLOR is set
  CI, NO_INPUT        force non-interactive mode

Files:
  ai-models.json   Claude and Codex model menus, JSON, next to the script.
                   Edit by hand or refresh with --update-models / [U].
                   Created with defaults on first use.

Exit codes:
  0   success
  1   model list update failed
  2   usage error
  3   missing dependency (no usable console)
  4   cancelled by user
  5   precondition failed (working directory missing)
  70  internal error (iteration cap tripped)
  other   exit code of the launched AI CLI, passed through
EOF
}


# =============================================================================
#  CLEANUP: every exit path arrives here
# =============================================================================
cleanup() {
  [ -n "$BF_COLOR" ] && printf '%s[0m%s[?25h' "$ESC" "$ESC" >&2
  [ -n "$MDL_LINES" ] && [ -f "$MDL_LINES" ] && rm -f "$MDL_LINES"
  return 0
}

on_interrupt() {
  cleanup
  printf '\n' >&2
  exit 4
}
trap on_interrupt INT TERM
trap cleanup EXIT


# =============================================================================
#  MAIN
# =============================================================================
main_loop() {
  STEP=engine
  while [ -n "$STEP" ]; do
    case "$STEP" in
      engine)          m_engine ;;
      cl_account)      m_cl_account ;;
      cl_model)        m_cl_model ;;
      cl_custom_model) m_cl_custom_model ;;
      cl_effort)       m_cl_effort ;;
      cl_perm)         m_cl_perm ;;
      cl_session)      m_cl_session ;;
      cl_verbose)      m_cl_verbose ;;
      cl_adddir)       m_cl_adddir ;;
      cl_sysprompt)    m_cl_sysprompt ;;
      cl_mcp)          m_cl_mcp ;;
      cl_tools)        m_cl_tools ;;
      cl_chrome)       m_cl_chrome ;;
      cl_worktree)     m_cl_worktree ;;
      cl_startup)      m_cl_startup ;;
      cl_ide)          m_cl_ide ;;
      cx_session)      m_cx_session ;;
      cx_model)        m_cx_model ;;
      cx_custom_model) m_cx_custom_model ;;
      cx_appr)         m_cx_appr ;;
      cx_search)       m_cx_search ;;
      cx_cd)           m_cx_cd ;;
      cx_prompt)       m_cx_prompt ;;
      gm_model)        m_gm_model ;;
      gm_appr)         m_gm_appr ;;
      gm_sandbox)      m_gm_sandbox ;;
      gm_session)      m_gm_session ;;
      gm_worktree)     m_gm_worktree ;;
      gm_dirs)         m_gm_dirs ;;
      gm_debug)        m_gm_debug ;;
      gm_prompt)       m_gm_prompt ;;
      ag_session)      m_ag_session ;;
      ag_perm)         m_ag_perm ;;
      ag_sandbox)      m_ag_sandbox ;;
      ag_dirs)         m_ag_dirs ;;
      ag_prompt)       m_ag_prompt ;;
      auth_setup)      m_auth_setup ;;
      env_fix)         m_env_fix ;;
      update_models)   m_update_models ;;
      confirm)         m_confirm ;;
      edit)            m_edit ;;
      chdir)           m_chdir ;;
      run)             run_cmd; STEP="" ;;
      quit)            BF_EXIT=0; STEP="" ;;
      *)               err "internal: unknown step '$STEP'"; BF_EXIT=70; STEP="" ;;
    esac
    [ -n "$BF_STOP" ] && STEP=""
  done
}

main() {
  detect_context
  parse_args "$@"
  [ -n "$BF_STOP" ] && exit "$BF_EXIT"
  [ "$BF_EXIT" != "0" ] && exit "$BF_EXIT"

  resolve_root

  if [ -n "$BF_FIXENV" ]; then
    env_fix_go
    exit "$BF_EXIT"
  fi
  if [ -n "$BF_UPDATE" ]; then
    models_update_go
    exit "$MDL_UPD_RC"
  fi
  if [ -n "$BF_REFRESH" ]; then
    models_refresh_go
    exit "$MDL_UPD_RC"
  fi

  # Opt-in launch-time refresh; fires at most once a day and is bounded by the
  # fetch timeout, so an offline machine stalls briefly once, not every start.
  [ -n "${AI_BAT_AUTO_UPDATE:-}" ] && auto_update_check

  # Non-interactive callers (CI, scheduler, another script) never see the menu,
  # so the tool stays schedulable.
  if [ -n "$BF_NONINTERACTIVE" ] || [ -n "$AI_KIND" ]; then
    if [ -z "$AI_KIND" ]; then
      err "no interactive console available; pass --ai <claude|codex|gemini|antigravity> or --help"
      exit 2
    fi
    build
    if [ -n "$BF_PRINT_ONLY" ]; then
      printf '%s\n' "$CMD"
      exit 0
    fi
    run_cmd
    exit "$BF_EXIT"
  fi

  main_loop
  exit "$BF_EXIT"
}

main "$@"
