{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.git;
in {
  options.kirk.git = {
    enable = mkEnableOption "git";

    userEmail = mkOption {
      type = types.str;
      description = "What email address to use for git.";
    };

    userName = mkOption {
      type = types.str;
      description = "Username to use for git.";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      userEmail = cfg.userEmail;
      userName = cfg.userName;
      delta = {
        enable = true;
        options = {
          features = "gruvmax-fang";
        };
      };
      includes = [
        # Delta plugins
        {
          path =
            pkgs.fetchFromGitHub {
              owner = "dandavison";
              repo = "delta";
              rev = "85e2f8e490498629a806af01b960e0510bff3973";
              sha256 = "sha256-vEv3HdLeI3ZXBCSmvd0x7DgEu+DiQqEwFf+WLDdL+4U=";
            }
            + "/themes.gitconfig";
        }
      ];
      aliases = {
        update = "submodule update --init --recursive";
        unstage = "restore --staged";
        d = "diff";
        dc = "diff --cached";
        c = "commit";
        a = "add .";
        ca = "commit -a";
        s = "status";
        su = "status -uno";
        co = "checkout --recurse-submodules";
        l = "log";
      };
      extraConfig = {
        push = {
          autoSetupRemote = true;
        };
        pull = {
          rebase = true;
        };
      };
    };
  };
}
