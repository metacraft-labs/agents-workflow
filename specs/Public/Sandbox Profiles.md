---
status: Early-Draft, Needs-Expansion
---
Sandbox profiles define how local executions are isolated. They are orthogonal to UI and to local/remote mode. The profile is resolved from config or flags and determines the runner that hosts the agent and its per‑task workspace.

Why sandboxes (threats and safety):
- Accidental breakage of the host (e.g., `rm -rf /`, package manager changes, daemon starts).
- Prompt‑injection induced exfiltration or persistence beyond the per‑task workspace.
- Network egress controls and secret hygiene (limit where credentials are visible and what endpoints are reachable).
- Determinism: immutable base layers with copy‑on‑write upper layers make runs reproducible and easy to clean up.

Baseline requirements:
- Per‑task workspace must be isolated from the real working tree (snapshot + CoW or equivalent).
- No writes outside the workspace; only approved read‑only mounts (e.g., credential stores) when needed.
- Non‑root execution whenever possible; explicit elevation required and audited when unavoidable.

Profile types (predefined):
- container: OCI container (Docker/Podman). Options include image, user/uid, mounts, network, seccomp/apparmor.
- vm: Lightweight Linux VM (Lima/Colima, Apple Virtualization.framework, WSL2/Hyper‑V). Options include image, resources, networking.
- bwrap: Userspace namespace sandbox via `bubblewrap` (Linux); optional seccomp, bind rules.
- firejail: Linux Firejail profile with caps/seccomp filters.
- nsjail: Linux `nsjail` with mount and cgroup limits.
- unsandboxed: Run directly on host (policy‑gated, for already isolated environments like dedicated VMs).

OS guidance (non‑exhaustive):
- Linux: prefer `container` (Docker/Podman). For host‑native, consider `bwrap`, `firejail`, or `nsjail` with OverlayFS for CoW.
- macOS: prefer `vm` (Lima/Colima) to get Linux CoW filesystems; run containers inside. macOS process sandboxes are not sufficient for our needs.
- Windows: prefer `vm` (WSL2/Hyper‑V) or `container` via Docker Desktop. Windows Sandbox/WDAG are out‑of‑scope for now.

Configuration:
- See [Configuration](Configuration.md) for `[[sandbox]]` entries (name, type, and options) and selecting a profile via `--runtime`/fleet or by name in config.

Notes:
- Snapshot preference and workspace mounting are described in [FS Snapshots/FS Snapshots Overview](FS%20Snapshots/FS%20Snapshots%20Overview.md). In fleets, snapshots are taken on the leader host only.
