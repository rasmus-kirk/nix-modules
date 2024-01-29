{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.terminalTools;
  tomlFormat = pkgs.formats.toml {};

  tealdeer-config = {
    updates = {
      auto_update = false;
      auto_update_interval_hours = 168;
    };
  };
in {
  options.kirk.terminalTools = {
    enable = mkEnableOption "Quality of life terminal tools";

    theme = mkOption {
      type = types.str;
      default = "gruvbox-dark";
      description = "What syntax highlighting colorscheme to use.";
    };

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable zsh integration for bat.";
    };

    autoUpdateTealdeer = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-update tealdeer.";
    };

    trashCleaner = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the trash-cli cleanup script";
      };
      persistance = mkOption {
        type = types.number;
        default = 30;
        description = "How many days a file stays in trash before getting cleaned up.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      fif() {
        if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
        rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
      }

      # bat
      alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
      alias bathelp='bat --plain --language=help'
      help() {
      	"$@" --help 2>&1 | bathelp
      }

      # exa
      alias ll="eza --icons --long"
      alias lh="eza --icons --long --all"
    '';

    systemd.user = mkIf cfg.trashCleaner.enable {
      timers = {
        trashCleaner = {
          Unit.Description = "Gets a japanese word from the Jiten dictionary";

          Timer = {
            OnCalendar = "daily";
            Persistent = "true"; # Run service immediately if last window was missed
            RandomizedDelaySec = "1h"; # Run service OnCalendar +- 1h
          };

          Install.WantedBy = ["timers.target"];
        };
      };

      services = {
        trashCleaner = {
          Unit.Description = "Updates the daily japanese word";

          Service = {
            ExecStart = "${pkgs.trash-cli}/bin/trash-empty -fv ${toString cfg.trashCleaner.persistance}";
            Type = "oneshot";
          };
        };
      };
    };

    # Generate tealdeer config
    xdg.configFile."tealdeer/config.toml" = mkIf cfg.autoUpdateTealdeer {
      source = tomlFormat.generate "tealdeer-config" tealdeer-config;
    };

    programs.bat = {
      enable = true;
      config = {
        theme = cfg.theme;
      };
    };

    home.packages = with pkgs; [
      rig # Random Identities for Privacy
      btop # Task Manager
      silver-searcher # Search in Files
      jq # JSON Parser
      tealdeer # TLDR for CLI Commands
      eza # Pretty ls
      fd # Find Files
      duf # Pretty df
      du-dust # Pretty du
      trash-cli # Trash Files in Terminal
      bat-extras.batman
    ];
  };
}
