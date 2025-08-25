## Multi‑OS Testing — Leader/Followers, Sync, and run_everywhere

### Summary

Enable agents to validate builds and tests across multiple operating systems in parallel with a simple, reliable flow:

- The Linux host acts as the leader workspace (preferred for CoW FsSnapshots and orchestration).
- One or more follower workspaces (macOS, Windows, Linux) mirror the leader via Mutagen high‑speed file sync.
- Each execution cycle fences the filesystem state (FsSnapshot + sync) and then invokes project‑defined commands everywhere via `run_everywhere`.

### Goals

- Deterministic, low‑latency propagation of file changes from leader to followers.
- Atomic test execution view based on a consistent leader FsSnapshot.
- Simple project integration via a single `run_everywhere` entrypoint and tagging.
- Minimal OS‑specific logic inside agents; orchestration handled by the runner.
- Avoid the complexity of filesystem snapshots on followers. The snapshots of the leader are sufficient to restore any filesystem state on the followers as well.

### Terminology

- **Leader**: The primary workspace on Linux (snapshot‑enabled when possible).
- **Followers**: Secondary workspaces on other OSes, receiving file updates via Mutagen.
- **Sync Fence**: An explicit operation ensuring all follower file trees match the leader FsSnapshot before execution.
- **run_everywhere**: Project command that runs an action (e.g., build/test) on selected hosts and returns output of the command execution to the agent running on the leader.

### Architecture

1) Workspace Topology
   - Leader path (e.g., `/workspaces/proj`) is the source of truth.
   - Mutagen sessions map leader→follower working directories with optimized ignores.
   - Followers are prepared using container/VM/native shells; Windows may still use the `S:` drive mapping even when not using the WinFsp overlay (which is not required in a follower configuration).

2) Execution Cycle
   - Agent edits files on the leader.
   - Runner executes `fs_snapshot_and_sync`:
     - Create a leader FsSnapshot (native CoW when available; FSKit/WinFsp overlay fallback otherwise).
     - Issue a sync fence: wait until Mutagen confirms followers are in sync with the leader snapshot content.
   - The agent is instructed to invoke `run_everywhere` with appropriate selectors in the agent instructions inserted automatically by agents-workflow.

3) Selectors
   - `--host <name>`: run on a single follower by host name.
   - `--tag <tag>`: run on all followers tagged with `<tag>` (e.g., `os=windows`, `gpu=nvidia`).
   By default, the supplied command is executed on all configured followers (the default).

### Snapshot Strategy

- Leader on CoW FS (ZFS/Btrfs/NILFS2):
  - Only the leader creates FsSnapshots; followers rely on sync fence to reflect that exact state.
- Leader without CoW (Windows‑only/macos‑only projects):
  - Use user‑space overlay (FSKit/WinFsp) for the leader to provide efficient CoW behavior.
  - Followers still rely on sync fence; no follower snapshots required.

### Mutagen Integration

- Use Mutagen to establish persistent, resilient sync sessions (bidirectional disabled; leader→followers only).
- Sync ignores: `node_modules`, `.venv`, `target`, `build`, large caches unless explicitly needed; per‑project config via `.agents/mutagen.yml`.
- Sync fence API: wait for `watchState == consistent` across all selected followers with a timeout and backoff.

### Project Contract: run_everywhere

The `run_everywhere` command is available in the dev environment of the project as part of the agent-workflow suite (which is pre-installed in the base docker images provided by agents-workflow (see `devcontainer-design.md`)):

- Parameter parsing for `--host`, `--tag`, `--all`, and pass‑through of the command/action (e.g., `build`, `test`, `lint`).
- Host catalog discovery (local file `.agents/hosts.json`, REST query, or env).
- Per‑host command adapters:
  - Linux: bash/zsh; container or native.
  - macOS: zsh; FSKit overlay mount path.
  - Windows: PowerShell or bash in MSYS; WinFsp overlay under `S:`.
- Exit code aggregation: return non‑zero if any selected host fails.

Illustrative usage:

```bash
# Run tests on all followers
.agents/run_everywhere test --all

# Run build only on Windows hosts
.agents/run_everywhere build --tag os=windows

# Run lint on a specific host
.agents/run_everywhere lint --host win-12
```

### REST Extensions (high‑level)

- `GET /api/v1/followers` → list configured followers (host, os, tags, status).
- `POST /api/v1/followers/sync-fence` → perform sync fence; returns states per follower.
- `POST /api/v1/run-everywhere` → body: { action, args, selectors }; streams per‑host logs via SSE.

### CLI Additions (high‑level)

- `aw followers list` — show followers and status.
- `aw followers sync-fence [--timeout s] [--tag ... | --host ... | --all]`
- `aw run-everywhere <action> [args...] [--tag ... | --host ... | --all]`

### Time‑Travel Integration

- The leader’s `fs_snapshot_and_sync` is inserted between edit operations and tool execution.
- SessionMoments are emitted before/after the fence; the FsSnapshot id is linked to the post‑fence SessionMoment.
- Seeking to that SessionMoment restores leader FsSnapshot; followers are re‑synced by issuing a fence before re‑execution.

### Devcontainer/Runner Notes

- Followers can be provisioned via devcontainers or native shells with the same project devshell.
- Credentials and environment normalization follow the base image’s credential propagation rules.
- Health checks verify Mutagen sessions and per‑host readiness before execution.

### Failure Modes

- Fence timeout: abort run_everywhere; report lagging followers and suggest narrowing selectors.
- Partial host failure: aggregate failures and return non‑zero; provide per‑host logs and artifacts.
- Sync divergence: force rescan/rebuild of stale directories; optionally clear ignores for critical paths.

### Open Questions

- Artifact collection and centralization strategy across followers.
- Test sharding and orchestration policies (e.g., split tests by tag or runtime).
- Security posture for follower access (SSH, certificates, RBAC via REST).


