## AW CLI — Command-Line and TUI Specification

### Overview

The AW CLI (`aw`) unifies local and remote workflows for launching and managing agent coding sessions. Running `aw` with no subcommands starts the TUI dashboard. Subcommands provide scriptable operations for task/session lifecycle, configuration, repository management, and developer ergonomics.

The CLI honors the layered configuration model in `docs/configuration.md` (system, user, project, project-user, env, CLI flags). Flags map from config keys using the `--a-b-c` convention and env var prefix `AGENTS_WORKFLOW_`.

### Primary Goals

- One tool for both the TUI dashboard and automation-ready commands
- First-class support for:
  - Local directory mode (PID-like files for discovery)
  - Remote REST service mode (on-prem/private cloud), aligned with `docs/rest-service.md`
  - Terminal multiplexers: tmux, zellij, screen
  - Devcontainers and local runtimes (including unsandboxed, policy-gated)
  - IDE integrations (VS Code, Cursor, Windsurf) and terminal-based agents

### Global Behavior and Flags

- `aw` (no args): Launches the TUI dashboard (default mode described below)
- Common global flags (apply to all subcommands unless noted):
  - `--mode <auto|local|rest>`: Discovery/operation mode. Default: `auto` (prefer local when in a repo with `.agents/`; otherwise rest if `network.apiUrl` configured)
  - `--repo <PATH|URL>`: Target repository (filesystem path in local mode; git URL otherwise)
  - `--project <NAME>`: Project/workspace name (REST mode)
  - `--json`: Emit machine-readable JSON
  - `--quiet`: Reduce output
  - `--log-level <debug|info|warn|error>`
  - `--no-color`

Configuration mapping examples:

- `network.apiUrl` ↔ `--network-api-url`, `AGENTS_WORKFLOW_NETWORK_API_URL`
- `tui.defaultMode` ↔ `--mode`
- `terminal.multiplexer` ↔ `--multiplexer <tmux|zellij|screen>`
- `editor.default` ↔ `--editor`
- `browserAutomation.enabled` ↔ `--browser-automation`, `AGENTS_WORKFLOW_BROWSER_AUTOMATION_ENABLED`
- `browserAutomation.profile` ↔ `--browser-profile`, `AGENTS_WORKFLOW_BROWSER_PROFILE`
- `browserAutomation.chatgptUsername` ↔ `--chatgpt-username`, `AGENTS_WORKFLOW_BROWSER_AUTOMATION_CHATGPT_USERNAME`
- `codex.workspace` ↔ `--codex-workspace`, `AGENTS_WORKFLOW_CODEX_WORKSPACE`

### Subcommands

#### 1) TUI

- `aw` or `aw tui [--mode <local|rest>] [--multiplexer <tmux|zellij|screen>]`
  - Starts the dashboard and auto-attaches to the active multiplexer session (creating one if needed).
  - Mode `rest`: connects to REST service to retrieve projects/repos/agents/branches and launches local (or remote via SSH) multiplexer windows for new tasks.
  - Mode `local`: operates in current repository (default), discovering running tasks via PID-like files in the filesystem.

TUI dashboard (simplified quick-launch UI):

- Top: fixed-height selectors for Project, Branch, Agent with filter input and arrow-key navigation (long lists scroll within the viewport).
- Bottom: multiline task description editor (resizable). A Start action launches the task.
- Existing task windows are already visible in the multiplexer; the dashboard focuses on selecting options and starting new tasks.

Task launch behavior in TUI:

- Creates a new multiplexer window immediately with split panes: right pane shows the agent activity; left pane starts a terminal or configured editor in the task-specific workspace mount.

#### 2) Tasks

- `aw task [create] [--prompt <TEXT> | --prompt-file <FILE>] [--repo <PATH|URL>] [--branch <NAME>] [--agent <TYPE>[@VERSION]] [--instances <N>] [--runtime <devcontainer|local|unsandboxed>] [--devcontainer-path <PATH>] [--labels k=v ...] [--delivery <pr|branch|patch>] [--target-branch <NAME>] [--browser-automation <true|false>] [--browser-profile <NAME>] [--chatgpt-username <NAME>] [--codex-workspace <WORKSPACE>] [--yes]`

Behavior:

- In local mode, prepares a per-task workspace using snapshot preference order (ZFS > Btrfs > Overlay > copy) and launches the agent.
- In rest mode, calls `POST /api/v1/tasks` with the provided parameters.
- Creates/updates a local PID-like session record when launching locally (see “Local Discovery”).
- When `--browser-automation true` (default), launches site-specific browser automation (e.g., Codex) using the selected agent browser profile. When `false`, web automation is skipped.
- Codex integration: if `--browser-profile` is not specified, discovers or creates a ChatGPT profile per `docs/browser-automation/codex.md`, optionally filtered by `--chatgpt-username`. Workspace is taken from `--codex-workspace` or config; branch is taken from `--branch`.
- Branch autocompletion uses standard git protocol:
  - Local mode: `git for-each-ref` on the repo; cached with debounce.
  - REST mode: server uses `git ls-remote`/refs against admin-configured URL to populate its cache; CLI/Web query capability endpoints for suggestions.

Draft flow (TUI/Web parity):

- CLI supports `--draft` to persist an editable draft; `aw task start <draft-id>` to submit.

#### 3) Sessions

- `aw session list [--status <...>] [--project <...>] [--repo <...>]`
- `aw session get <SESSION_ID>`
- `aw session logs <SESSION_ID> [-f] [--tail <N>]`
- `aw session events <SESSION_ID> [-f]`
- `aw session stop <SESSION_ID>`
- `aw session pause <SESSION_ID>`
- `aw session resume <SESSION_ID>`
- `aw session cancel <SESSION_ID>`

Behavior:

- Local mode reads session records from filesystem; `logs -f` tails the agent log.
- REST mode proxies to the service and uses SSE for `events -f`.

#### 4) Attach / Open

- `aw attach <SESSION_ID> [--pane <left|right|full>]` — Attach to the multiplexer window for a session.
- `aw open ide <SESSION_ID> --ide <vscode|cursor|windsurf>` — Open IDE on the session workspace.

Remote sessions:

- When a session runs on another machine (VM or remote host), the REST service returns SSH connection details. `aw attach` uses these to open a remote multiplexer session (e.g., `ssh -t host tmux attach -t <name>`), or to run zellij/screen equivalents.

#### 5) Repositories and Projects

- `aw repo list` (local: from recent usage; rest: from workspace projects)
- `aw repo add <PATH|URL>` (local only by default)
- `aw repo remove <PATH|URL>` (local; protected confirm)
- `aw project list` (rest mode)

#### 6) Runtimes, Agents, Hosts (capabilities)

- `aw agents list`
- `aw runtimes list`
- `aw hosts list`

REST-backed: proxies to `/api/v1/agents`, `/api/v1/runtimes`, `/api/v1/hosts`.

#### 7) Config (Git-like)

- `aw config get <key> [--scope <system|user|project|project-user>] [--explain]`
- `aw config set <key> <value> [--scope ...] [--enforced]` (system scope only can be enforced)
- `aw config list [--scope ...] [--show-origin]`
- `aw config unset <key> [--scope ...]`

Mirrors `docs/configuration.md` including provenance, precedence, and Windows behavior.

#### 8) Service and WebUI (local developer convenience)

- `aw serve rest [--local] [--bind 127.0.0.1] [--port <P>] [--db <URL|PATH>]`
  - Starts the REST service (localhost-only by default with `--local`).
- `aw webui [--local] [--port <P>] [--rest <URL>]`
  - Serves the WebUI for local use; in `--local` it binds to `127.0.0.1` and hides admin features.

#### 9) Utilities
#### 10) Followers and Multi‑OS

- `aw followers list` — List configured follower hosts and tags.
- `aw followers sync-fence [--timeout <sec>] [--tag <k=v>]... [--host <name>]... [--all]` — Perform a synchronization fence, ensuring followers match the leader workspace state.
- `aw run-everywhere [--tag <k=v>]... [--host <name>]... [--all] [--] <command> [args...]` — Invoke run‑everywhere on selected followers.

#### 11) Connectivity (Overlay/Relay)

- `aw connect keys [--provider netbird|tailscale|auto] [--tag <name>]...` — Request session connectivity credentials.
- `aw connect handshake --session <id> [--hosts <list>] [--timeout <sec>]` — Initiate and wait for follower acks; prints per‑host status.
- Relay utilities (fallback):
  - `aw relay tail --session <id> --host <name> [--stream stdout|stderr|status]`
  - `aw relay send --session <id> --host <name> --control <json>`
  - `aw relay socks5 --session <id> --bind 127.0.0.1:1080` — Start a local SOCKS5 relay for this session (client‑hosted rendezvous).


- `aw doctor` — Environment diagnostics (snapshot providers, multiplexer availability, docker/devcontainer, git).
- `aw completion [bash|zsh|fish|pwsh]` — Shell completions.

### Local Discovery (PID-like Files)

Purpose: Enable TUI and CLI to enumerate and manage running local sessions without a server.

Location:

- Per-repo: `.agents/sessions/` within the repository root.
- Optional user index: `~/.config/agents-workflow/sessions/` to aggregate across repos (TUI may use this for “recent sessions”).

Record format (JSON example):

```json
{
  "id": "01HVZ6K9T1N8S6M3V3Q3F0X5B7",
  "repoPath": "/home/user/src/app",
  "workspacePath": "/workspaces/agent-01HVZ6K9",
  "agent": {"type": "claude-code", "version": "latest"},
  "runtime": {"type": "devcontainer", "devcontainerPath": ".devcontainer/devcontainer.json"},
  "multiplexer": {"kind": "tmux", "session": "aw:01HVZ6K9", "window": 3, "paneLeft": "%5", "paneRight": "%6"},
  "pids": {"agent": 12345},
  "status": "running",
  "startedAt": "2025-01-01T12:00:00Z",
  "logPath": "/workspaces/agent-01HVZ6K9/.agents/logs/agent.log"
}
```

Creation and lifecycle:

- `aw task` writes the record on successful launch and updates status transitions.
- On normal termination, the record is finalized (endedAt, final status) and moved to an archive file.
- Crash/unclean exit detection: stale PID check on startup; records marked as `failed` with reason.

### Multiplexer Integration

Selection:

- `--multiplexer` flag or `terminal.multiplexer` config determines which tool is used. Autodetect if unset (tmux > zellij > screen if found in PATH).

Layout on launch:

- Create a new window in the current session (or create a session if none) with two panes:
  - Right: agent activity (logs/stream)
  - Left: terminal in the per-task workspace (or launch editor if configured)

Remote attach:

- Using SSH details from the REST service, run the appropriate attach command remotely (e.g., `ssh -t host tmux new-session -A -s aw:<id> ...`).

Devcontainers:

- When `runtime.type=devcontainer`, run the multiplexer and both panes inside the container context. The left pane starts a login shell or editor; the right follows the agent process output.

### Runtime and Workspace Behavior

- Snapshot selection priority: ZFS → Btrfs → OverlayFS → copy (`cp --reflink=auto` when available), per `docs/fs-snapshots/overview.md`.
- Unsandboxed local runs require explicit `--runtime unsandboxed` and may be disabled by admin policy.
- Delivery modes: PR, Branch push, Patch artifact (as in REST spec).

### IDE and Terminal Agent Integration

- `aw open ide` opens VS Code / Cursor / Windsurf for the per-task workspace (local or via remote commands as provided by the REST service).
- Terminal-based agent alongside GUI editor: user can choose an editor in the left pane while the agent runs on the right; alternatively, `--editor` launches `vim`/`emacs`/other terminal editor with an integrated terminal.

### Examples

Create a task locally and immediately open TUI window/panes:

```bash
aw task --prompt "Refactor checkout service for reliability" --repo . --agent openhands --runtime devcontainer --branch main --instances 2
```

Specify a browser profile and disable automation explicitly:

```bash
aw task --prompt "Kick off Codex" --browser-profile work-codex --browser-automation false
```

List and tail logs for sessions:

```bash
aw session list --status running --json
aw session logs 01HVZ6K9T1N8S6M3V3Q3F0X5B7 -f --tail 500
```

Attach to a running session window:

```bash
aw attach 01HVZ6K9T1N8S6M3V3Q3F0X5B7 --pane left
```

Run the TUI against a REST service:

```bash
aw tui --mode rest --multiplexer tmux
```

Start local REST service and WebUI for a single developer:

```bash
aw serve rest --local --port 8081
aw webui --local --port 8080 --rest http://127.0.0.1:8081
```

### Exit Codes

- 0 success; non-zero on validation, environment, or network errors (with descriptive stderr messages).

### Security Notes

- Honors admin-enforced config. Secrets never printed. Unsandboxed runtime gated and requires explicit opt-in.


