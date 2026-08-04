@echo off
cd /d "%~dp0"
setlocal enabledelayedexpansion

:: ============================================================
::  AI LAUNCHER - BetterGuard Web Source
::  Picks an AI CLI first (Claude / Codex / Gemini / Antigravity)
::  then exposes that engine's own parameter settings.
:: ============================================================

:: ============================================================
::  GIT BASH AUTO-DETECT (required by Claude on Windows)
:: ============================================================
if not defined CLAUDE_CODE_GIT_BASH_PATH (
    if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    ) else if exist "C:\Program Files\Git\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe"
    ) else if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=C:\Program Files (x86)\Git\bin\bash.exe"
    ) else if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" (
        set "CLAUDE_CODE_GIT_BASH_PATH=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
    ) else (
        for /f "delims=" %%p in ('where bash.exe 2^>nul') do (
            set "CLAUDE_CODE_GIT_BASH_PATH=%%p"
        )
    )
)

:: ============================================================
::  TOP-LEVEL: AI SELECTION
:: ============================================================
:ai_select
cls
echo ============================================================
echo   AI Launcher - BetterGuard Web Source
echo ============================================================
echo.
echo --- Select AI ---
echo   [1] Claude       (Anthropic - full agentic CLI)
echo   [2] Codex        (OpenAI - codex CLI, supports --yolo)
echo   [3] Gemini       (Google - gemini CLI, supports --yolo)
echo   [4] Antigravity  (Google - agy terminal agent)
echo.
echo   [F] Fix Environment (set git-bash + PATH permanently)
echo   [Q] Quit
echo.
set /p AI_CHOICE="Select AI [1-4/F/Q] (default=1): "
if "%AI_CHOICE%"=="" set AI_CHOICE=1
if /i "%AI_CHOICE%"=="F" goto env_fix
if /i "%AI_CHOICE%"=="Q" goto end
if "%AI_CHOICE%"=="1" goto claude_flow
if "%AI_CHOICE%"=="2" goto codex_flow
if "%AI_CHOICE%"=="3" goto gemini_flow
if "%AI_CHOICE%"=="4" goto antigravity_flow
goto ai_select


:: ============================================================
:: ============================================================
::  CLAUDE FLOW
:: ============================================================
:: ============================================================
:claude_flow
set "AI_NAME=Claude"
set "CLAUDE_CONFIG_DIR="
set "CMD=claude --dangerously-skip-permissions"

if not defined CLAUDE_CODE_GIT_BASH_PATH (
    echo.
    echo  [ERROR] Git Bash not found. Install from https://git-scm.com/downloads/win
    echo  Or set CLAUDE_CODE_GIT_BASH_PATH manually.
    pause
)

cls
echo ============================================================
echo   Claude Code Launcher
echo ============================================================
echo.

:: --- 0. ACCOUNT SELECTION ---
:account
echo --- Account ---
echo   [1] Account 1 - Primary (Chrome)
echo   [2] Account 2 - Fallback (Brave)
echo   [3] Default (no account switch)
echo   [A] Auth Setup (first-time login for both accounts)
echo.
set /p ACC_CHOICE="Select account [1-3/A] (default=1): "
if "%ACC_CHOICE%"=="" set ACC_CHOICE=1

if /i "%ACC_CHOICE%"=="A" goto auth_setup
if "%ACC_CHOICE%"=="1" (
    set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc1"
    echo   ^> Using Account 1
)
if "%ACC_CHOICE%"=="2" (
    set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc2"
    echo   ^> Using Account 2
)
if "%ACC_CHOICE%"=="3" (
    echo   ^> Using default config
)
echo.

:: --- 1. MODEL SELECTION ---
:model
echo --- Model Selection ---
echo   [1] claude-opus-5                (Opus 5 - newest Opus)
echo   [2] claude-fable-5               (Fable 5)
echo   [3] claude-opus-4-8              (Opus 4.8 - adaptive thinking, effort defaults to high)
echo   [4] claude-opus-4-7              (Opus 4.7 - adaptive thinking)
echo   [5] claude-sonnet-4-6            (Sonnet 4.6 - extended + adaptive thinking)
echo   [6] claude-haiku-4-5-20251001    (Haiku 4.5 - fast, extended thinking)
echo   [7] claude-opus-4-6              (Opus 4.6 - extended + adaptive thinking)
echo   [8] Custom model ID              (fetches available models from API)
echo   [9] Skip (no --model flag)
echo.
set /p MODEL_CHOICE="Select model [1-9] (default=1): "
if "%MODEL_CHOICE%"=="" set MODEL_CHOICE=1
if "%MODEL_CHOICE%"=="1" set "CMD=%CMD% --model claude-opus-5"
if "%MODEL_CHOICE%"=="2" set "CMD=%CMD% --model claude-fable-5"
if "%MODEL_CHOICE%"=="3" set "CMD=%CMD% --model claude-opus-4-8"
if "%MODEL_CHOICE%"=="4" set "CMD=%CMD% --model claude-opus-4-7"
if "%MODEL_CHOICE%"=="5" set "CMD=%CMD% --model claude-sonnet-4-6"
if "%MODEL_CHOICE%"=="6" set "CMD=%CMD% --model claude-haiku-4-5-20251001"
if "%MODEL_CHOICE%"=="7" set "CMD=%CMD% --model claude-opus-4-6"
if "%MODEL_CHOICE%"=="8" goto custom_model
goto after_model

:custom_model
echo.
echo   Fetching available models from Anthropic API...
echo.

:: Build PowerShell script in temp file to avoid batch escaping issues
set "PS_SCRIPT=%TEMP%\claude_fetch_models.ps1"

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
echo     Write-Host '   Models available on your account:' -ForegroundColor Green >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     $resp.data ^| Sort-Object id ^| ForEach-Object { >> "!PS_SCRIPT!"
echo         $name = if ($_.display_name) { $_.display_name } else { '' } >> "!PS_SCRIPT!"
echo         Write-Host ('     ' + $_.id.PadRight(45) + $name) >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     Write-Host '   Aliases (always available):' -ForegroundColor Cyan >> "!PS_SCRIPT!"
echo     Write-Host '     opus, sonnet, haiku, opus[1m], sonnet[1m], opusplan' >> "!PS_SCRIPT!"
echo } catch { >> "!PS_SCRIPT!"
echo     if ($_.Exception.Message -eq 'NO_KEY') { >> "!PS_SCRIPT!"
echo         Write-Host '   No ANTHROPIC_API_KEY found. Showing static list.' -ForegroundColor Yellow >> "!PS_SCRIPT!"
echo     } else { >> "!PS_SCRIPT!"
echo         Write-Host "   API call failed: $($_.Exception.Message)" -ForegroundColor Yellow >> "!PS_SCRIPT!"
echo     } >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     Write-Host '   Aliases:  opus, sonnet, haiku, opus[1m], sonnet[1m], opusplan' >> "!PS_SCRIPT!"
echo     Write-Host '' >> "!PS_SCRIPT!"
echo     Write-Host '   Opus:     claude-opus-4-7  claude-opus-4-6  claude-opus-4-5-20251101  claude-opus-4-20250514' >> "!PS_SCRIPT!"
echo     Write-Host '   Sonnet:   claude-sonnet-4-20250514  claude-3-7-sonnet-20250219  claude-3-5-sonnet-20241022' >> "!PS_SCRIPT!"
echo     Write-Host '   Haiku:    claude-3-5-haiku-20241022' >> "!PS_SCRIPT!"
echo } >> "!PS_SCRIPT!"

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_SCRIPT!"
del "!PS_SCRIPT!" >nul 2>&1

echo.
echo   Tip: Use /model inside Claude to switch models during a session.
echo.
set /p CUSTOM_MODEL="Enter model ID: "
set "CMD=!CMD! --model !CUSTOM_MODEL!"

:after_model
echo.

:: --- 2. EFFORT LEVEL ---
:budget
echo --- Effort Level ---
echo   [1] Default (no flag)
echo   [2] Low       (fast, light reasoning)
echo   [3] Medium    (standard tasks)
echo   [4] High      (complex tasks)
echo   [5] Extra High (deep analysis)
echo   [6] Maximum   (hardest problems)
echo.
set /p BUDGET_CHOICE="Select effort [1-6] (default=1): "
if "%BUDGET_CHOICE%"=="" set BUDGET_CHOICE=1
if "%BUDGET_CHOICE%"=="2" set "CMD=%CMD% --effort low"
if "%BUDGET_CHOICE%"=="3" set "CMD=%CMD% --effort medium"
if "%BUDGET_CHOICE%"=="4" set "CMD=%CMD% --effort high"
if "%BUDGET_CHOICE%"=="5" set "CMD=%CMD% --effort xhigh"
if "%BUDGET_CHOICE%"=="6" set "CMD=%CMD% --effort max"
echo.

:: --- 3. PERMISSION MODE ---
:permissions
echo --- Permission Mode ---
echo   [1] bypassPermissions     (--dangerously-skip-permissions, default)
echo   [2] dontAsk               (auto-approve, no prompts)
echo   [3] acceptEdits           (auto-approve edits, prompt for commands)
echo   [4] default               (prompt for sensitive actions)
echo   [5] plan                  (show plan first, then execute)
echo   [6] auto                  (auto-approves safe actions, asks for risky ones)
echo.
set /p PERM_CHOICE="Select permission mode [1-6] (default=1): "
if "%PERM_CHOICE%"=="" set PERM_CHOICE=1
if "%PERM_CHOICE%"=="2" set "CMD=claude --permission-mode dontAsk" & goto rebuild_perm
if "%PERM_CHOICE%"=="3" set "CMD=claude --permission-mode acceptEdits" & goto rebuild_perm
if "%PERM_CHOICE%"=="4" set "CMD=claude --permission-mode default" & goto rebuild_perm
if "%PERM_CHOICE%"=="5" set "CMD=claude --permission-mode plan" & goto rebuild_perm
if "%PERM_CHOICE%"=="6" set "CMD=claude --permission-mode auto" & goto rebuild_perm
goto after_perm

:rebuild_perm
set "PERM_BASE=!CMD!"
set "CMD=!PERM_BASE!"
if "%MODEL_CHOICE%"=="1" set "CMD=!CMD! --model claude-opus-5"
if "%MODEL_CHOICE%"=="2" set "CMD=!CMD! --model claude-fable-5"
if "%MODEL_CHOICE%"=="3" set "CMD=!CMD! --model claude-opus-4-8"
if "%MODEL_CHOICE%"=="4" set "CMD=!CMD! --model claude-opus-4-7"
if "%MODEL_CHOICE%"=="5" set "CMD=!CMD! --model claude-sonnet-4-6"
if "%MODEL_CHOICE%"=="6" set "CMD=!CMD! --model claude-haiku-4-5-20251001"
if "%MODEL_CHOICE%"=="7" set "CMD=!CMD! --model claude-opus-4-6"
if "%MODEL_CHOICE%"=="8" set "CMD=!CMD! --model !CUSTOM_MODEL!"

:after_perm
echo.

:: --- 4. SESSION OPTIONS ---
:session
echo --- Session Options ---
echo   [1] New session (default)
echo   [2] Continue last session (-c)
echo   [3] Resume specific session (-r)
echo   [4] Session with custom name (-n)
echo   [5] Continue last as fork (-c --fork-session)  (new session ID, original stays intact)
echo   [6] Resume from GitHub PR (--from-pr)          (reopens the session linked to a PR)
echo.
set /p SESSION_CHOICE="Select session option [1-6] (default=1): "
if "%SESSION_CHOICE%"=="" set SESSION_CHOICE=1
if "%SESSION_CHOICE%"=="2" set "CMD=%CMD% -c"
if "%SESSION_CHOICE%"=="3" (
    set /p SESSION_ID="Enter session ID or name: "
    set "CMD=!CMD! -r !SESSION_ID!"
)
if "%SESSION_CHOICE%"=="4" (
    set /p SESSION_NAME="Enter session name: "
    set "CMD=!CMD! -n !SESSION_NAME!"
)
if "%SESSION_CHOICE%"=="5" set "CMD=%CMD% -c --fork-session"
if "%SESSION_CHOICE%"=="6" (
    set /p PR_REF="Enter PR number or URL (empty = picker): "
    if "!PR_REF!"=="" (set "CMD=!CMD! --from-pr") else (set "CMD=!CMD! --from-pr !PR_REF!")
)
echo.

:: --- 5. VERBOSE / DEBUG ---
:verbose
echo --- Verbose / Debug ---
echo   [1] Normal (default)
echo   [2] Verbose (--verbose)
echo   [3] Debug (--debug)
echo   [4] Debug with category filter
echo.
set /p VERBOSE_CHOICE="Select [1-4] (default=1): "
if "%VERBOSE_CHOICE%"=="" set VERBOSE_CHOICE=1
if "%VERBOSE_CHOICE%"=="2" set "CMD=%CMD% --verbose"
if "%VERBOSE_CHOICE%"=="3" set "CMD=%CMD% --debug"
if "%VERBOSE_CHOICE%"=="4" (
    set /p DEBUG_CATS="Enter debug categories (comma-separated): "
    set "CMD=!CMD! --debug !DEBUG_CATS!"
)
echo.

:: --- 6. ADDITIONAL DIRECTORIES ---
:adddir
echo --- Additional Working Directories ---
echo   [1] None (default)
echo   [2] Add directories (--add-dir)
echo.
set /p ADDDIR_CHOICE="Select [1-2] (default=1): "
if "%ADDDIR_CHOICE%"=="" set ADDDIR_CHOICE=1
if "%ADDDIR_CHOICE%"=="2" (
    set /p ADD_DIRS="Enter directory paths (space-separated): "
    set "CMD=!CMD! --add-dir !ADD_DIRS!"
)
echo.

:: --- 7. SYSTEM PROMPT ---
:sysprompt
echo --- System Prompt ---
echo   [1] Default (use CLAUDE.md)
echo   [2] Append custom text (--append-system-prompt)
echo   [3] Replace entirely (--system-prompt)
echo.
set /p SYSPROMPT_CHOICE="Select [1-3] (default=1): "
if "%SYSPROMPT_CHOICE%"=="" set SYSPROMPT_CHOICE=1
if "%SYSPROMPT_CHOICE%"=="2" (
    set /p APPEND_PROMPT="Enter text to append: "
    set "CMD=!CMD! --append-system-prompt "!APPEND_PROMPT!""
)
if "%SYSPROMPT_CHOICE%"=="3" (
    set /p REPLACE_PROMPT="Enter replacement system prompt: "
    set "CMD=!CMD! --system-prompt "!REPLACE_PROMPT!""
)
echo.

:: --- 8. MCP CONFIG ---
:mcp
echo --- MCP Server Config ---
echo   [1] None (default)
echo   [2] Load MCP config (--mcp-config)
echo   [3] Strict MCP only (--strict-mcp-config)
echo.
set /p MCP_CHOICE="Select [1-3] (default=1): "
if "%MCP_CHOICE%"=="" set MCP_CHOICE=1
if "%MCP_CHOICE%"=="2" (
    set /p MCP_FILE="Enter MCP config file path: "
    set "CMD=!CMD! --mcp-config !MCP_FILE!"
)
if "%MCP_CHOICE%"=="3" (
    set /p MCP_FILE="Enter MCP config file path: "
    set "CMD=!CMD! --strict-mcp-config --mcp-config !MCP_FILE!"
)
echo.

:: --- 9. TOOL RESTRICTIONS ---
:tools
echo --- Tool Restrictions ---
echo   [1] All tools (default)
echo   [2] Specific tools only (--tools)
echo   [3] No tools (--tools "")
echo.
set /p TOOLS_CHOICE="Select [1-3] (default=1): "
if "%TOOLS_CHOICE%"=="" set TOOLS_CHOICE=1
if "%TOOLS_CHOICE%"=="2" (
    echo   Available: Bash, Edit, Read, Write, Glob, Grep, WebFetch, WebSearch, Task, NotebookEdit
    set /p TOOLS_LIST="Enter tool names (comma-separated): "
    set "CMD=!CMD! --tools "!TOOLS_LIST!""
)
if "%TOOLS_CHOICE%"=="3" set "CMD=!CMD! --tools """
echo.

:: --- 10. BROWSER / CHROME ---
:chrome
echo --- Chrome Browser Integration ---
echo   [1] Default
echo   [2] Enable (--chrome)
echo   [3] Disable (--no-chrome)
echo.
set /p CHROME_CHOICE="Select [1-3] (default=1): "
if "%CHROME_CHOICE%"=="" set CHROME_CHOICE=1
if "%CHROME_CHOICE%"=="2" set "CMD=%CMD% --chrome"
if "%CHROME_CHOICE%"=="3" set "CMD=%CMD% --no-chrome"
echo.

:: --- 11. GIT WORKTREE ---
:worktree
echo --- Git Worktree ---
echo   [1] None (default)          (work directly in this checkout)
echo   [2] New worktree (-w)       (isolated repo copy - experiment without touching main checkout)
echo   [3] Worktree + tmux (--tmux) (worktree in its own tmux pane - needs tmux installed)
echo.
set /p WT_CHOICE="Select [1-3] (default=1): "
if "%WT_CHOICE%"=="" set WT_CHOICE=1
if "%WT_CHOICE%"=="2" (
    set /p WT_NAME="Worktree name (empty = auto): "
    if "!WT_NAME!"=="" (set "CMD=!CMD! -w") else (set "CMD=!CMD! -w !WT_NAME!")
)
if "%WT_CHOICE%"=="3" (
    set /p WT_NAME="Worktree name (empty = auto): "
    if "!WT_NAME!"=="" (set "CMD=!CMD! -w --tmux") else (set "CMD=!CMD! -w !WT_NAME! --tmux")
)
echo.

:: --- 12. STARTUP MODE ---
:startupmode
echo --- Startup Mode ---
echo   [1] Normal (default)        (loads hooks, plugins, CLAUDE.md as usual)
echo   [2] Bare (--bare)           (fastest startup, skips hooks/plugins/CLAUDE.md - WARNING: needs ANTHROPIC_API_KEY, account OAuth will NOT work)
echo   [3] Safe Mode (--safe-mode) (all customizations off - use to troubleshoot broken config)
echo.
set /p STARTUP_CHOICE="Select [1-3] (default=1): "
if "%STARTUP_CHOICE%"=="" set STARTUP_CHOICE=1
if "%STARTUP_CHOICE%"=="2" set "CMD=%CMD% --bare"
if "%STARTUP_CHOICE%"=="3" set "CMD=%CMD% --safe-mode"
echo.

:: --- 13. IDE INTEGRATION ---
:ide
echo --- IDE Integration ---
echo   [1] None (default)
echo   [2] Auto-connect (--ide)    (attaches to VS Code/JetBrains if exactly one is open)
echo.
set /p IDE_CHOICE="Select [1-2] (default=1): "
if "%IDE_CHOICE%"=="" set IDE_CHOICE=1
if "%IDE_CHOICE%"=="2" set "CMD=%CMD% --ide"
echo.
goto confirm


:: ============================================================
:: ============================================================
::  CODEX FLOW (OpenAI)
:: ============================================================
:: ============================================================
:codex_flow
set "AI_NAME=Codex"
set "CLAUDE_CONFIG_DIR="
set "CMD=codex"
cls
echo ============================================================
echo   Codex Launcher (OpenAI)
echo ============================================================
echo.

:: --- Session (subcommand must come first) ---
echo --- Session ---
echo   [1] New session (default)
echo   [2] Resume (picker)
echo   [3] Resume last (--last)
echo   [4] Fork (picker)
echo   [5] Fork last (--last)
echo.
set /p CX_SESS="Select [1-5] (default=1): "
if "%CX_SESS%"=="" set CX_SESS=1
if "%CX_SESS%"=="2" set "CMD=codex resume"
if "%CX_SESS%"=="3" set "CMD=codex resume --last"
if "%CX_SESS%"=="4" set "CMD=codex fork"
if "%CX_SESS%"=="5" set "CMD=codex fork --last"
echo.

:: --- Model ---
echo --- Model ---
echo   [1] Default (from ~/.codex/config.toml)
echo   [2] Custom model id
echo.
set /p CX_MODEL="Select [1-2] (default=1): "
if "%CX_MODEL%"=="" set CX_MODEL=1
if "%CX_MODEL%"=="2" (
    echo   Hint: e.g. gpt-5-codex, gpt-5, o3, o4-mini
    set /p CX_MODEL_ID="Enter model id: "
    set "CMD=!CMD! -m !CX_MODEL_ID!"
)
echo.

:: --- Approval / Sandbox ---
echo --- Approval / Sandbox ---
echo   [1] Default (codex built-in policy)
echo   [2] YOLO - bypass ALL approvals and sandbox (--yolo)   [DANGEROUS]
echo   [3] Full access, never ask     (-s danger-full-access -a never)
echo   [4] Workspace-write, on-request (-s workspace-write -a on-request)
echo   [5] Read-only, untrusted        (-s read-only -a untrusted)
echo.
set /p CX_APPR="Select [1-5] (default=1): "
if "%CX_APPR%"=="" set CX_APPR=1
if "%CX_APPR%"=="2" set "CMD=!CMD! --yolo"
if "%CX_APPR%"=="3" set "CMD=!CMD! -s danger-full-access -a never"
if "%CX_APPR%"=="4" set "CMD=!CMD! -s workspace-write -a on-request"
if "%CX_APPR%"=="5" set "CMD=!CMD! -s read-only -a untrusted"
echo.

:: --- Web Search ---
echo --- Web Search ---
echo   [1] Off (default)
echo   [2] On (--search)
echo.
set /p CX_SEARCH="Select [1-2] (default=1): "
if "%CX_SEARCH%"=="2" set "CMD=!CMD! --search"
echo.

:: --- Working Directory ---
echo --- Working Directory ---
echo   [1] This folder (default)
echo   [2] Custom root (-C)
echo.
set /p CX_CD="Select [1-2] (default=1): "
if "%CX_CD%"=="2" (
    set /p CX_CD_DIR="Enter directory path: "
    set "CMD=!CMD! -C "!CX_CD_DIR!""
)
echo.

:: --- Initial Prompt (new session only) ---
if not "%CX_SESS%"=="1" goto confirm
echo --- Initial Prompt ---
echo   [1] None - start interactive (default)
echo   [2] Provide an initial prompt
echo.
set /p CX_HASPROMPT="Select [1-2] (default=1): "
if "%CX_HASPROMPT%"=="2" (
    set /p CX_PROMPT="Enter prompt: "
    set "CMD=!CMD! "!CX_PROMPT!""
)
echo.
goto confirm


:: ============================================================
:: ============================================================
::  GEMINI FLOW (Google)
:: ============================================================
:: ============================================================
:gemini_flow
set "AI_NAME=Gemini"
set "CLAUDE_CONFIG_DIR="
set "CMD=gemini"
cls
echo ============================================================
echo   Gemini Launcher (Google)
echo ============================================================
echo.

:: --- Model ---
echo --- Model ---
echo   [1] Default (from config)
echo   [2] Custom model id
echo.
set /p GM_MODEL="Select [1-2] (default=1): "
if "%GM_MODEL%"=="" set GM_MODEL=1
if "%GM_MODEL%"=="2" (
    echo   Hint: e.g. gemini-2.5-pro, gemini-2.5-flash
    set /p GM_MODEL_ID="Enter model id: "
    set "CMD=!CMD! -m !GM_MODEL_ID!"
)
echo.

:: --- Approval Mode ---
echo --- Approval Mode ---
echo   [1] Default (prompt for approval)
echo   [2] YOLO - auto-accept all actions (--yolo)   [DANGEROUS]
echo   [3] Auto-edit (--approval-mode auto_edit)
echo   [4] Plan / read-only (--approval-mode plan)
echo.
set /p GM_APPR="Select [1-4] (default=1): "
if "%GM_APPR%"=="" set GM_APPR=1
if "%GM_APPR%"=="2" set "CMD=!CMD! --yolo"
if "%GM_APPR%"=="3" set "CMD=!CMD! --approval-mode auto_edit"
if "%GM_APPR%"=="4" set "CMD=!CMD! --approval-mode plan"
echo.

:: --- Sandbox ---
echo --- Sandbox ---
echo   [1] Off (default)
echo   [2] On (--sandbox)
echo.
set /p GM_SANDBOX="Select [1-2] (default=1): "
if "%GM_SANDBOX%"=="2" set "CMD=!CMD! --sandbox"
echo.

:: --- Session ---
echo --- Session ---
echo   [1] New session (default)
echo   [2] Resume latest (--resume latest)
echo   [3] Resume by index (--resume N)
echo.
set /p GM_SESS="Select [1-3] (default=1): "
if "%GM_SESS%"=="" set GM_SESS=1
if "%GM_SESS%"=="2" set "CMD=!CMD! --resume latest"
if "%GM_SESS%"=="3" (
    set /p GM_RIDX="Enter session index number: "
    set "CMD=!CMD! --resume !GM_RIDX!"
)
echo.

:: --- Git Worktree ---
echo --- Git Worktree ---
echo   [1] None (default)
echo   [2] New worktree (-w)
echo.
set /p GM_WT="Select [1-2] (default=1): "
if "%GM_WT%"=="2" (
    set /p GM_WT_NAME="Worktree name (empty = auto): "
    if "!GM_WT_NAME!"=="" (set "CMD=!CMD! -w") else (set "CMD=!CMD! -w !GM_WT_NAME!")
)
echo.

:: --- Additional Directories ---
echo --- Additional Working Directories ---
echo   [1] None (default)
echo   [2] Include directories (--include-directories)
echo.
set /p GM_DIRS="Select [1-2] (default=1): "
if "%GM_DIRS%"=="2" (
    set /p GM_DIR_LIST="Enter directories (comma-separated): "
    set "CMD=!CMD! --include-directories !GM_DIR_LIST!"
)
echo.

:: --- Debug ---
echo --- Debug ---
echo   [1] Off (default)
echo   [2] On (--debug)
echo.
set /p GM_DEBUG="Select [1-2] (default=1): "
if "%GM_DEBUG%"=="2" set "CMD=!CMD! --debug"
echo.

:: --- Initial Prompt ---
echo --- Initial Prompt ---
echo   [1] None - start interactive (default)
echo   [2] Interactive with prompt (-i)
echo   [3] Headless / non-interactive (-p)
echo.
set /p GM_PROMPT_MODE="Select [1-3] (default=1): "
if "%GM_PROMPT_MODE%"=="2" (
    set /p GM_PROMPT="Enter prompt: "
    set "CMD=!CMD! -i "!GM_PROMPT!""
)
if "%GM_PROMPT_MODE%"=="3" (
    set /p GM_PROMPT="Enter prompt: "
    set "CMD=!CMD! -p "!GM_PROMPT!""
)
echo.
goto confirm


:: ============================================================
:: ============================================================
::  ANTIGRAVITY FLOW (Google - agy terminal agent)
:: ============================================================
:: ============================================================
:antigravity_flow
set "AI_NAME=Antigravity"
set "CLAUDE_CONFIG_DIR="
set "CMD=agy"
cls
echo ============================================================
echo   Antigravity Launcher (Google - agy CLI agent)
echo ============================================================
echo.

:: --- Session ---
echo --- Session ---
echo   [1] New conversation (default)
echo   [2] Continue most recent (-c)
echo   [3] Resume by conversation ID (--conversation)
echo.
set /p AG_SESS="Select [1-3] (default=1): "
if "%AG_SESS%"=="" set AG_SESS=1
if "%AG_SESS%"=="2" set "CMD=!CMD! -c"
if "%AG_SESS%"=="3" (
    set /p AG_CONV="Enter conversation ID: "
    set "CMD=!CMD! --conversation !AG_CONV!"
)
echo.

:: --- Permissions ---
echo --- Permissions ---
echo   [1] Default (prompt for each tool action)
echo   [2] YOLO - auto-approve all tool permissions (--dangerously-skip-permissions)   [DANGEROUS]
echo.
set /p AG_PERM="Select [1-2] (default=1): "
if "%AG_PERM%"=="2" set "CMD=!CMD! --dangerously-skip-permissions"
echo.

:: --- Sandbox ---
echo --- Sandbox ---
echo   [1] Off (default)
echo   [2] On - terminal restrictions (--sandbox)
echo.
set /p AG_SB="Select [1-2] (default=1): "
if "%AG_SB%"=="2" set "CMD=!CMD! --sandbox"
echo.

:: --- Additional Directories ---
echo --- Additional Working Directories ---
echo   [1] None (default)
echo   [2] Add a directory (--add-dir)
echo.
set /p AG_DIR="Select [1-2] (default=1): "
if "%AG_DIR%"=="2" (
    set /p AG_DIR_PATH="Enter directory path: "
    set "CMD=!CMD! --add-dir "!AG_DIR_PATH!""
)
echo.

:: --- Initial Prompt ---
echo --- Initial Prompt ---
echo   [1] None - start interactive (default)
echo   [2] Interactive with prompt (-i)
echo   [3] Headless / print once (-p)
echo.
set /p AG_PM="Select [1-3] (default=1): "
if "%AG_PM%"=="2" (
    set /p AG_PROMPT="Enter prompt: "
    set "CMD=!CMD! -i "!AG_PROMPT!""
)
if "%AG_PM%"=="3" (
    set /p AG_PROMPT="Enter prompt: "
    set "CMD=!CMD! -p "!AG_PROMPT!""
)
echo.
goto confirm


:: ============================================================
:: ============================================================
::  SHARED: CONFIRM / EDIT / RUN
:: ============================================================
:: ============================================================
:confirm
echo ============================================================
echo   AI:  %AI_NAME%
if defined CLAUDE_CONFIG_DIR echo   CONFIG: %CLAUDE_CONFIG_DIR%
echo.
echo   FINAL COMMAND:
echo   %CMD%
echo.
echo ============================================================
echo.
echo   [Y] Launch    [E] Edit command manually    [R] AI menu    [Q] Quit
echo.
set /p LAUNCH="Select [Y/E/R/Q] (default=Y): "
if "%LAUNCH%"=="" set LAUNCH=Y
if /i "%LAUNCH%"=="Y" goto run
if /i "%LAUNCH%"=="E" goto edit
if /i "%LAUNCH%"=="R" goto ai_select
if /i "%LAUNCH%"=="Q" goto end
goto confirm

:edit
set /p CMD="Edit command and press Enter: "
echo.
echo Updated command: %CMD%
echo.
set /p LAUNCH2="Launch? [Y/N]: "
if /i "%LAUNCH2%"=="Y" goto run
goto confirm

:run
echo.
echo Launching %AI_NAME%...
echo.
call %CMD%
echo.
echo   %AI_NAME% session ended.
echo.
pause
goto end


:: ============================================================
:: AUTH SETUP (Claude - first-time login for both accounts)
:: ============================================================
:auth_setup
cls
echo ============================================================
echo   Claude Code - Account Auth Setup
echo ============================================================
echo.
echo  This will log in two accounts. Run once.
echo  After this, just pick [1] or [2] from the account menu.
echo.

echo  ----------------------------------------
echo   ACCOUNT 1 - Log in via CHROME
echo  ----------------------------------------
echo  Make sure Account 1 is logged in on claude.ai in Chrome.
echo  Browser will open for OAuth.
echo.
echo  Press any key when ready...
pause >nul
echo.
set CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc1
claude auth login
echo.
echo  [Account 1 status:]
claude auth status
echo.

echo  ----------------------------------------
echo   ACCOUNT 2 - Log in via BRAVE
echo  ----------------------------------------
echo  Make sure Account 2 is logged in on claude.ai in Brave.
echo  If Chrome opens instead, copy the URL to Brave.
echo.
echo  Press any key when ready...
pause >nul
echo.
set CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-acc2
claude auth login
echo.
echo  [Account 2 status:]
claude auth status
echo.

echo  ========================================
echo   Done! Both accounts saved.
echo   Press any key to return to the Claude menu.
echo  ========================================
pause >nul
goto claude_flow

:: ============================================================
:: ENV FIX (set git-bash + PATH permanently)
:: ============================================================
:env_fix
cls
echo ============================================================
echo   Environment Fix
echo ============================================================
echo.

:: Set git-bash permanently
echo  Setting CLAUDE_CODE_GIT_BASH_PATH permanently...
setx CLAUDE_CODE_GIT_BASH_PATH "%CLAUDE_CODE_GIT_BASH_PATH%"
echo  [OK] Git Bash: %CLAUDE_CODE_GIT_BASH_PATH%
echo.

:: Add this folder to PATH
set "AI_DIR=%~dp0"
if "!AI_DIR:~-1!"=="\" set "AI_DIR=!AI_DIR:~0,-1!"
echo  Checking PATH for %AI_DIR%...
echo %PATH% | findstr /i /c:"%AI_DIR%" >nul 2>nul
if %errorlevel% equ 0 (
    echo  [OK] Already in PATH
) else (
    echo  Adding to user PATH...
    for /f "tokens=*" %%A in ('powershell -command "[Environment]::GetEnvironmentVariable('Path','User')"') do set "UPATH=%%A"
    setx PATH "!UPATH!;!AI_DIR!"
    echo  [OK] Added to PATH
)

echo.
echo  Done! Restart your terminal for PATH changes.
echo  Press any key to return to the AI menu.
pause >nul
goto ai_select

:end
endlocal
