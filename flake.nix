{
  description = "agents-workflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
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

          # AI Coding Assistants (latest versions from nixpkgs-unstable)
          pkgs.goose-cli # Goose AI coding assistant
          pkgs.claude-code # Claude Code - agentic coding tool
          pkgs.gemini-cli # Gemini CLI
          pkgs.codex # OpenAI Codex CLI (Rust implementation)
          pkgs.opencode # OpenCode AI coding assistant
        ]
        # Optional schema/validation tooling (only if available in this nixpkgs)
        ++ (builtins.filter (x: x != null) [
          (if pkgs ? taplo then pkgs.taplo else null)
          (if (builtins.hasAttr "nodePackages" pkgs) && (builtins.hasAttr "ajv-cli" pkgs.nodePackages)
           then pkgs.nodePackages."ajv-cli" else null)
        ])
        ++ pkgs.lib.optionals isLinux [
          # Linux-only filesystem utilities for snapshot functionality
          pkgs.zfs # ZFS utilities for copy-on-write snapshots
          pkgs.btrfs-progs # Btrfs utilities for subvolume snapshots
        ] ++ pkgs.lib.optionals isDarwin [
          # macOS-only VM manager
          pkgs.lima # Linux virtual machines on macOS
        ];

        shellHook = ''
          echo "Agent workflow development environment loaded"
          # Provide a convenience function to launch Docson without global install
          docson () { npx -y docson "$@"; }
          echo "Tip: run: docson -d ./specs/schemas  # then open http://localhost:3000"
        '';
      };
    });
  };
}
