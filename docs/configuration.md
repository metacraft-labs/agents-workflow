## Configuration System Specification for Blocksense Agents-Workflow

### Overview and Goals

The Blocksense Agents-Workflow project uses a layered configuration system to manage settings. Multiple configuration sources (from built-in defaults to user overrides) are merged in priority order to offer flexibility while enabling enterprise control.

- **Multi-layered configuration**: Support settings from defaults, system administrators, user preferences, project-specific configs, environment variables, and command-line flags. Higher-priority layers override lower-priority ones.
- **Admin enforceability**: Allow system administrators to enforce settings that users cannot override.
- **Cross-platform consistency**: Provide a uniform configuration interface across Linux, Windows, macOS, and mobile, while leveraging platform conventions.
- **Declarative, user-friendly format**: Use TOML for config files; validate against a schema.
- **Proven patterns**: Inspired by tools like Git and Visual Studio Code with layered config models ([Git](https://git-scm.com/docs/git-config), [VS Code](https://code.visualstudio.com/docs/getstarted/settings)).

### Configuration Layers and Precedence

Configuration values are loaded from multiple sources in a specific order of precedence (later wins unless enforced):

- **Built-in Defaults**: Safe fallback values baked into the application.

- **System (OS-Level) Configuration**: System-wide/administrator settings for all users on a machine. Example paths:
  - Linux: `/etc/xdg/agents-workflow/config.toml` (per [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html))
  - Windows: `%ProgramData%\\Blocksense\\AgentsWorkflow\\config.toml` (and optionally registry)
  - macOS: `/Library/Application Support/Blocksense/AgentsWorkflow/config.toml`
  By default, user and project configs can override system config unless marked enforced.

- **User Profile Configuration**: User-specific global preferences:
  - Linux/macOS: `~/.config/agents-workflow/config.toml` (XDG)
  - Windows: support both `%APPDATA%\\Blocksense\\AgentsWorkflow\\config.toml` and `~/.config/agents-workflow/config.toml`. If both exist, `~/.config/...` takes precedence for consistency.
  This layer overrides any non-enforced system settings. This mirrors Git’s global config ([git-config](https://git-scm.com/docs/git-config)).

- **Project Repository Configuration**: Project-provided settings stored in the repository. Agents-Workflow already uses an `.agents` folder; per-project configuration lives in:
  - Repository path: `.agents/config.toml`
  These settings override user-global preferences because they are more specific.

- **Per-Project User Overrides**: A user may override a project’s settings without changing the repo. Store in the repo but outside version control:
  - Repository path: `.agents/local/config.toml` (recommended to be gitignored)
  This layer has higher priority than project repository config.

- **Environment Variables**: Session-scoped overrides with the highest non-admin priority. All environment variables are prefixed with `AGENTS_WORKFLOW_`. See Environment Variables below for mapping.

- **Command-Line Arguments (per-setting flags)**: Highest priority. Each setting has its own flag (for example, `--log-level debug`). There is no generic `--config` flag.

**Precedence rule**: Higher-priority layers override lower-priority ones. Composite structures follow schema-defined merge/replace rules; by default a higher layer replaces lower-layer lists/tables.

**Exception — Admin Enforced Settings**: System-level config values can be marked enforced so no lower-priority source (including environment or CLI) can override them. If a user attempts an override, the application warns and retains the enforced value.

### Administrative Enforcement Mechanism

- **Marking values as enforced**: The system config file supports tagging keys as enforced (syntax TBD). Enforced keys are treated as read-only by the app.
- **Override blocking**: Overrides for enforced keys are ignored with a clear message similar to “This setting is enforced by your administrator.”
- **File system protections**: System config paths (e.g., `/etc/xdg`, `%ProgramData%`) require elevated permissions, preventing tampering at the source. Application logic further blocks runtime overrides.
- **Optional policy integration**: Optionally read platform-native policies (Windows Group Policy/Registry, macOS configuration profiles) as system-level enforced config.

### Cross-Platform Considerations

- **Linux/Unix**: Follow XDG conventions. System config in `$XDG_CONFIG_DIRS/agents-workflow/config.toml` (default `/etc/xdg`), user config in `$XDG_CONFIG_HOME/agents-workflow/config.toml` (default `~/.config/agents-workflow/config.toml`). Project config discovery traverses parents to find `.agents/config.toml` (inspired by [Cargo config discovery](https://doc.rust-lang.org/cargo/reference/config.html)).

- **Windows**: Primary user config may be either `%APPDATA%\\Blocksense\\AgentsWorkflow\\config.toml` or `~/.config/agents-workflow/config.toml`. For users who prefer consistency, `~/.config/...` is supported on Windows and takes precedence if both exist. System-wide config lives under `%ProgramData%\\Blocksense\\AgentsWorkflow\\config.toml`. Optional registry integration (e.g., `HKLM\\Software\\Blocksense\\AgentsWorkflow\\...`) can supply policies.

- **macOS**: Support XDG when set, otherwise use `~/Library/Application Support/Blocksense/AgentsWorkflow/config.toml` for user and `/Library/Application Support/Blocksense/AgentsWorkflow/config.toml` for system. Managed profiles are treated as system enforced.

- **Mobile (iOS/Android)**: No filesystem/env/CLI. Defaults compiled in, managed config via MDM, user preferences via in-app settings. The conceptual precedence remains the same.

### Configuration File Format (TOML) and Schema

All persistent configuration files use TOML. Configuration is validated against a versioned schema.

- **Example**:

```toml
[core]
projectRoot = "/home/user/myproj"
timeout = 30

[features]
enableX = true
enableY = false

[network]
apiUrl = "https://api.example.com"
```

- **Merging logic**:
  - Simple values: higher-priority value overwrites lower.
  - Tables/arrays: higher-priority replaces by default; selective merging may be defined per key in the schema.
- **Validation and errors**: Files with invalid types/keys are rejected with helpful messages.

### Command-Line Interface for Settings (no generic --config)

There is no `--config` key=value flag. Each setting has a dedicated flag. Mapping rules:

- **Mapping**: TOML key `a.b.c` → CLI flag `--a-b-c`.
- **Booleans**: `--feature-x` to enable, `--no-feature-x` to disable (if applicable).
- **Examples**:
  - `--log-level debug`
  - `--timeout 45`
  - `--network-api-url https://corp.example.com`

CLI flags have the highest priority (unless an admin-enforced value exists).

### Environment Variables (prefix: AGENTS_WORKFLOW_)

All environment variables are prefixed with `AGENTS_WORKFLOW_` for clarity in scripts and CI.

- **Mapping**: TOML key `a.b.c` → env var `AGENTS_WORKFLOW_A_B_C`.
- **Characters**: Dots and hyphens become underscores; names are uppercased.
- **Examples**:
  - `AGENTS_WORKFLOW_LOG_LEVEL=debug`
  - `AGENTS_WORKFLOW_TIMEOUT=45`
  - `AGENTS_WORKFLOW_NETWORK_API_URL=https://corp.example.com`

Environment variables override file-based configuration for that process (unless enforced).

### Project and Per-Project User Configuration

Agents-Workflow stores per-project configuration under the repository’s `.agents` directory:

- **Project config (shared)**: `.agents/config.toml` (committed to VCS).
- **User override (local)**: `.agents/local/config.toml` (gitignored), higher priority than project config.

This replaces earlier proposals like `.agents-workflow.toml` to consolidate project settings in one folder already used by the tool.

### Configuration Discovery, Provenance, and Debugging

The configuration loader records the origin of every setting (file path, environment variable name, CLI flag) and whether it is enforced.

- **Debug logging**: When log level is `debug`, CLI tools report which config files/directories they attempt to read and which were found/loaded, in precedence order.
- **Explain resolution**: When querying a setting, a detailed report shows all occurrences across layers and explains which source won and why (including enforcement).

### Git-like Configuration Command

Provide a dedicated command to read and modify configuration, inspired by `git config`. Example interface (command name illustrative):

```bash
agents-workflow config get core.timeout --explain
agents-workflow config set core.timeout 45 --scope user
agents-workflow config set network.apiUrl https://corp.example.com --scope system --enforced
agents-workflow config list --scope project --show-origin
agents-workflow config unset features.enableY --scope project-user
```

- **Scopes**: `system`, `user`, `project` (repo `.agents/config.toml`), `project-user` (repo `.agents/local/config.toml`).
- **Show origin**: `--show-origin` displays file paths or `ENV/CLI` for values; `--explain` prints a merge trace and enforcement notes.
- **Windows behavior**: For `--scope user` on Windows, reads both `%APPDATA%` and `~/.config`; writes default to `~/.config/agents-workflow/config.toml` unless `--win-appdata` is specified.

### Editor experience in `agent-task`

The `agent-task` command opens an editor for the task description. The loaded buffer contains commented guidance and indicates the action to be executed after the editor closes. This action depends on configuration, and the template must include the configuration source responsible for it.

Example template (comments start with `#`):

```text
# Blocksense Agents-Workflow: Describe the task to perform below the separator.
# Lines starting with '#' are ignored.
#
# After you save and close, the following action will run:
#   start-work
# (source: project config at .agents/config.toml)
#
# You can change the default action via either:
#   - CLI: --action <start-work|get-task|...>
#   - Config key: core.defaultAction (see agents-workflow config --help)
---

```

This requires configuration provenance to be preserved so the editor can display the setting’s origin.

### User Experience and Examples

- **Out-of-the-box defaults**: The internal defaults are used when no config is present.

- **User-level customization**: Add preferences to `~/.config/agents-workflow/config.toml`. Example:

```toml
[core]
editor = "vim"
maxAgents = 10
```

- **Project-specific config (maintainer)**: Commit `.agents/config.toml`:

```toml
[features]
enableY = true
```

- **Project-specific user override**: Create `.agents/local/config.toml` (gitignored):

```toml
[features]
enableY = false
```

- **Admin enforcement**: In `/etc/xdg/agents-workflow/config.toml`, set and enforce:

```toml
[network]
apiUrl = "https://corporate-proxy.example.com"
enforced = true  # syntax illustrative
```

CLI attempts like `--network-api-url https://other.example.com` or `AGENTS_WORKFLOW_NETWORK_API_URL=...` are ignored with a clear message.

- **One-off overrides**:
  - Environment: `AGENTS_WORKFLOW_LOG_LEVEL=debug agent-task ...`
  - CLI: `agent-task --log-level debug ...`

### Inspiration and Analogous Systems

- **Git**: hierarchical config ([docs](https://git-scm.com/docs/git-config)).
- **VS Code**: user/workspace settings with precedence ([docs](https://code.visualstudio.com/docs/getstarted/settings)).
- **Cargo**: TOML config, discovery, env var overrides ([docs](https://doc.rust-lang.org/cargo/reference/config.html)).
- **XDG Base Directory & FHS**: standard file locations ([spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)).

### Conclusion

Agents-Workflow provides a layered, schema-validated configuration system with clear precedence, robust admin enforcement, and full provenance. Environment variables use the `AGENTS_WORKFLOW_` prefix; CLI uses per-setting flags only. Windows supports `~/.config` alongside `%APPDATA%`, with `~/.config` taking precedence when both are present. Project configuration is consolidated under `.agents/`. A Git-like configuration command and debug logging make configuration behavior transparent and explainable.


