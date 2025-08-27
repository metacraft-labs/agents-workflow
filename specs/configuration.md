
## AW Configuration

### Overview

* `aw config` subcommand with Git-like interface for reading and updating configuration.
* Schema validation on both config file loading and CLI-based modification.
* Precedence for `~/.config` over `%APPDATA%` on Windows only when both are present.
* Motivation and support for tracking the origin of each configuration value, with use cases such as: debug-level log reporting, enforced setting explanation, and editor pre-fill mes
sages.

Layered configuration supports system, user, project, and project-user scopes. Values can also be supplied via environment variables and CLI flags. See `specs/cli-spec.md` for flag mappings.

### Keys

- browserAutomation.enabled: boolean — enable/disable site automation.
- browserAutomation.profile: string — preferred agent browser profile name.
- browserAutomation.chatgptUsername: string — optional default ChatGPT username used for profile discovery.
- codex.workspace: string — default Codex workspace to select before pressing "Code".

### Behavior

- CLI flags override environment, which override project-user, project, user, then system scope.
- On Windows, `~/.config` takes precedence over `%APPDATA%` only when both are present.
- The CLI can read, write, and explain config values via `aw config`.

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

Example TOML (partial):

```toml
logLevel = "info"
mode = "auto"

[tui]
defaultMode = "auto"

[terminal]
multiplexer = "tmux"

[editor]
default = "nvim"

[network]
apiUrl = "https://aw.example.internal/api"

[browserAutomation]
enabled = true
profile = "work-codex"
chatgptUsername = "alice@example.com"

[codex]
workspace = "main"

[repo]
supportedAgents = "all" # or ["codex","claude","cursor"]

  [repo.init]
  vcs = "git"
  devenv = "nix"
  devcontainer = true
  direnv = true
  taskRunner = "just"
```

Notes:
- `supportedAgents` accepts "all" or an explicit array of agent names; the CLI may normalize this value internally.
- `devenv` accepts values like `nix`, `spack`, `bazel`, `none`/`no`, or `custom`.
