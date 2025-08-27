
## AW Configuration

### Overview

* `aw config` subcommand with Git-like interface for reading and updating configuration.
* Schema validation on both config file loading and CLI-based modification.
* Precedence for `~/.config` over `%APPDATA%` on Windows only when both are present.
* Motivation and support for tracking the origin of each configuration value, with use cases such as: debug-level log reporting, enforced setting explanation, and editor pre-fill mes
sages.

Layered configuration supports system, user, project, and project-user scopes. Values can also be supplied via environment variables and CLI flags. See [cli-spec](cli-spec.md) for flag mappings.

### Mapping Rules (Flags ↔ Config ↔ ENV/JSON)

To keep things mechanical and predictable:

- TOML sections correspond to subcommand groups (e.g., `[repo]` for `aw repo ...`).
- Option keys preserve dashes in TOML (e.g., `default-mode`, `task-runner`).
- JSON and environment variables replace dashes with underscores. ENV vars keep the `AGENTS_WORKFLOW_` prefix.

Examples:

- Flag `--remote-server` ↔ TOML `remote-server` ↔ ENV `AGENTS_WORKFLOW_REMOTE_SERVER`
- Per-server URLs are defined under `[[server]]` entries; `remote-server` may refer to a server `name` or be a raw URL.
- Flag `--network-api-url` (rarely needed) maps to a specific server entry’s `url`.
- Flag `--task-runner` ↔ TOML `repo.task-runner` ↔ ENV `AGENTS_WORKFLOW_REPO_TASK_RUNNER`

### Keys

- browserAutomation.enabled: boolean — enable/disable site automation.
- browserAutomation.profile: string — preferred agent browser profile name.
- browserAutomation.chatgptUsername: string — optional default ChatGPT username used for profile discovery.
- codex.workspace: string — default Codex workspace to select before pressing "Code".
- remote-server: string — either a known server `name` (from `[[server]]`) or a raw URL. If set, AW uses REST; otherwise it uses local SQLite state.

### Behavior

- CLI flags override environment, which override project-user, project, user, then system scope.
- On Windows, `~/.config` takes precedence over `%APPDATA%` only when both are present.
- The CLI can read, write, and explain config values via `aw config`.
- Backend selection: if `remote-server` is set (by flag/env/config), AW uses the REST API; otherwise it uses the local SQLite database.
- Repo detection: when `--repo` is not specified, AW walks parent directories to find a VCS root among supported systems; commands requiring a repo fail with a clear error when none is found.

### Validation

- The configuration file format is TOML, validated against a single holistic JSON Schema:
  - Schema: `specs/schemas/config.schema.json` (draft 2020-12)
  - Method: parse TOML → convert to a JSON data model → validate against the schema
  - Editors: tools like Taplo can use the JSON Schema to provide completions and diagnostics

- DRY definitions: the schema uses `$defs` for shared enums and shapes reused across the CLI (e.g., `Mode`, `Multiplexer`, `Vcs`, `DevEnv`, `TaskRunner`, `AgentName`, `SupportedAgents`).

Tools in the dev shell:

- `taplo` (taplo-cli): TOML validation with JSON Schema mapping
- `ajv` (ajv-cli): JSON Schema validator for JSON instances
- `docson` (via shell function): local schema viewer using `npx` (no global install)

Examples (use Just targets inside the Nix dev shell):

```bash
# Validate all JSON Schemas (meta-schema compile)
just conf-schema-validate

# Check TOML files with Taplo
just conf-schema-taplo-check

# Preview the schemas with Docson (serves http://localhost:3000)
just conf-schema-docs
```

Tip: from the host without entering the shell explicitly, you can run any target via:

```bash
nix develop --command just conf-schema-validate
```

### Servers, Fleets, and Sandboxes

AW supports declaring remote servers, fleets (multi-environment presets), and sandbox profiles.

```toml
remote-server = "office-1"  # optional; can be a name from [[server]] or a raw URL

[[server]]
name = "office-1"
url  = "https://aw.office-1.corp/api"

[[server]]
name = "office-2"
url  = "https://aw.office-2.corp/api"

# Fleets define a combination of local testing strategies and remote servers
# to be used as presets in multi-OS or multi-environment tasks.

[[fleet]]
name = "default"  # chosen when no other fleet is provided

  [[fleet.member]]
  type = "container"   # refers to a sandbox profile by name (see [[sandbox]] below)
  profile = "container"

  [[fleet.member]]
  type = "remote"      # special value; not a sandbox profile
  url  = "https://aw.office-1.corp/api"  # or `server = "office-1"`

[[sandbox]]
name = "container"
type = "container"      # predefined types with their own options (TBD)
```

Flags and mapping:
- `--remote-server <NAME|URL>` selects a server (overrides `remote-server` in config).
- `--fleet <NAME>` selects a fleet; default is the fleet named `default`.

### Example TOML (partial)

```toml
logLevel = "info"

[terminal]
multiplexer = "tmux"

[editor]
default = "nvim"

[network]
api-url = "https://deprecated.example.invalid"  # prefer [[server]] + remote-server

[browserAutomation]
enabled = true
profile = "work-codex"
chatgpt-username = "alice@example.com"

[codex]
workspace = "main"

[repo]
supported-agents = "all" # or ["codex","claude","cursor"]

  [repo.init]
  vcs = "git"
  devenv = "nix"
  devcontainer = true
  direnv = true
  task-runner = "just"
```

Notes:
- `supported-agents` accepts "all" or an explicit array of agent names; the CLI may normalize this value internally.
- `devenv` accepts values like `nix`, `spack`, `bazel`, `none`/`no`, or `custom`.

ENV examples:

```
AGENTS_WORKFLOW_REMOTE_SERVER=office-1
AGENTS_WORKFLOW_REPO_SUPPORTED_AGENTS=all
```
