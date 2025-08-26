
## AW Configuration

### Overview

* `aw config` subcommand with Git-like interface for reading and updating configuration.
* Schema validation on both config file loading and CLI-based modification.
* Precedence for `~/.config` over `%APPDATA%` on Windows only when both are present.
* Motivation and support for tracking the origin of each configuration value, with use cases such as: debug-level log reporting, enforced setting explanation, and editor pre-fill mes
sages.

Layered configuration supports system, user, project, and project-user scopes. Values can also be supplied via environment variables and CLI flags. See `docs/cli-spec.md` for flag mappings.

### Keys

- browserAutomation.enabled: boolean — enable/disable site automation.
- browserAutomation.profile: string — preferred agent browser profile name.
- browserAutomation.chatgptUsername: string — optional default ChatGPT username used for profile discovery.
- codex.workspace: string — default Codex workspace to select before pressing "Code".

### Behavior

- CLI flags override environment, which override project-user, project, user, then system scope.
- On Windows, `~/.config` takes precedence over `%APPDATA%` only when both are present.
- The CLI can read, write, and explain config values via `aw config`.
