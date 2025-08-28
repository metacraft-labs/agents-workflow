{
  description = "agents-workflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs = {
    self,
    nixpkgs,
    git-hooks,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    checks = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
      preCommit = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          lint-specs = {
            enable = true;
            name = "Lint Markdown specs";
            entry = "just lint-specs";
            language = "system";
            pass_filenames = false;
          };
        };
      };
    in {
      pre-commit-check = preCommit;
    });
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true; # Allow unfree packages like claude-code
        };
        agent-task-script = pkgs.writeShellScriptBin "agent-task" ''
          PATH=${pkgs.lib.makeBinPath [
            pkgs.ruby
            pkgs.goose-cli
            pkgs.claude-code
            pkgs.gemini-cli
            pkgs.codex
            pkgs.opencode
          ]}:$PATH
          exec ruby ${./bin/agent-task} "$@"
        '';
        get-task = pkgs.writeShellScriptBin "get-task" ''
          exec ${pkgs.ruby}/bin/ruby ${./bin/get-task} "$@"
        '';
        start-work = pkgs.writeShellScriptBin "start-work" ''
          exec ${pkgs.ruby}/bin/ruby ${./bin/start-work} "$@"
        '';
        agent-utils = pkgs.symlinkJoin {
          name = "agent-utils";
          paths = [get-task start-work];
        };
      in {
        agent-task = agent-task-script;
        agent-utils = agent-utils;
      }
    );

    apps = forAllSystems (system: {
      agent-task = {
        type = "app";
        program = "${self.packages.${system}.agent-task}/bin/agent-task";
      };
      default = self.apps.${system}.agent-task;
    });

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # Allow unfree packages like claude-code
      };
      isLinux = pkgs.stdenv.isLinux;
      isDarwin = pkgs.stdenv.isDarwin;
    in {
      default = pkgs.mkShell {
        buildInputs = [
          pkgs.just
          pkgs.ruby
          pkgs.bundler
          pkgs.rubocop
          pkgs.git
          pkgs.fossil
          pkgs.mercurial
          pkgs.nodejs # for npx-based docson helper
          # Mermaid validation (diagram syntax)
          (pkgs.nodePackages."@mermaid-js/mermaid-cli")
          pkgs.noto-fonts

          # Markdown linting & link/prose checking
          (pkgs.nodePackages.markdownlint-cli2)
          pkgs.lychee
          pkgs.vale
          (pkgs.nodePackages.cspell)

          # AI Coding Assistants (latest versions from nixpkgs-unstable)
          pkgs.goose-cli # Goose AI coding assistant
          pkgs.claude-code # Claude Code - agentic coding tool
          pkgs.gemini-cli # Gemini CLI
          pkgs.codex # OpenAI Codex CLI (Rust implementation)
          pkgs.opencode # OpenCode AI coding assistant
        ]
        ++ self.checks.${system}.pre-commit-check.enabledPackages
        # Optional schema/validation tooling (only if available in this nixpkgs)
        ++ (builtins.filter (x: x != null) [
          (if pkgs ? taplo then pkgs.taplo else null)
          (if (builtins.hasAttr "nodePackages" pkgs) && (builtins.hasAttr "ajv-cli" pkgs.nodePackages)
           then pkgs.nodePackages."ajv-cli" else null)
        ])
        ++ pkgs.lib.optionals isLinux [
          # Use Chromium on Linux for mermaid-cli's Puppeteer
          pkgs.chromium
          # Linux-only filesystem utilities for snapshot functionality
          pkgs.zfs # ZFS utilities for copy-on-write snapshots
          pkgs.btrfs-progs # Btrfs utilities for subvolume snapshots
        ] ++ pkgs.lib.optionals isDarwin [
          # macOS-only VM manager
          pkgs.lima # Linux virtual machines on macOS
        ];

        shellHook = ''
          # Install git pre-commit hook invoking our Nix-defined hooks
          ${self.checks.${system}.pre-commit-check.shellHook}
          echo "Agent workflow development environment loaded"
          # Provide a convenience function for Docson; no fallbacks in Nix shell
          docson () {
            if command -v docson >/dev/null 2>&1; then
              command docson "$@"
              return
            fi
            if [ -n "''${IN_NIX_SHELL:-}" ]; then
              echo "Docson is not available in this Nix dev shell. Add it to flake.nix (or choose an alternative) — no fallbacks allowed." >&2
              return 127
            fi
            if command -v npx >/dev/null 2>&1; then
              npx -y docson "$@"
            else
              echo "Docson not found and npx unavailable. Install Docson or enter nix develop with it provisioned." >&2
              return 127
            fi
          }
          echo "Tip: run: docson -d ./specs/schemas  # then open http://localhost:3000"
          # Ensure mermaid-cli (mmdc) uses system Chrome/Chromium when present
          if command -v chromium >/dev/null 2>&1; then
            export PUPPETEER_EXECUTABLE_PATH="$(command -v chromium)"
          elif command -v google-chrome >/dev/null 2>&1; then
            export PUPPETEER_EXECUTABLE_PATH="$(command -v google-chrome)"
          elif command -v google-chrome-stable >/dev/null 2>&1; then
            export PUPPETEER_EXECUTABLE_PATH="$(command -v google-chrome-stable)"
          fi
          export PUPPETEER_PRODUCT=chrome
        '';
      };
    });
  };
}
