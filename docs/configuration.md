
Thanks for the clarifications. I’ll revise the specification to include:

* `aw config` subcommand with Git-like interface for reading and updating configuration.
* Schema validation on both config file loading and CLI-based modification.
* Precedence for `~/.config` over `%APPDATA%` on Windows only when both are present.
* Motivation and support for tracking the origin of each configuration value, with use cases such as: debug-level log reporting, enforced setting explanation, and editor pre-fill messages.

I’ll update the specification accordingly and present a refined version that reflects these requirements.
