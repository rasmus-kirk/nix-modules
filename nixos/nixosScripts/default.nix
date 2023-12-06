{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeManagerScripts;

  nos-update = pkgs.writeShellApplication {
    name = "nos-update";
    text = ''
      nix flake update ${configDir}
    '';
  };

  nos-upgrade = pkgs.writeShellApplication {
    name = "nos-upgrade";
    text = ''
      # Update, switch to new config, and cleanup
      ${hm-update}/bin/hm-update &&
      ${hm-rebuild}/bin/hm-rebuild &&
    '';
  };

  nos-rebuild = pkgs.writeShellApplication {
    name = "nos-rebuild";
    text = ''
      # Update the inputs of this repo on every rebuild
      nix flake lock --update-input kirk-modules ${configDir}
      # Switch configuration, backing up files
      nixos-rebuild switch --flake ${configDir}#${cfg.machine}
    '';
  };
in {
  options.kirk.nixosScripts = {
    enable = mkEnableOption ''
      Nixos scripts

      Required options:
      - `machine`
    '';

    machine = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "REQUIRED! The machine to run on.";
    };

    configDir = mkOption {
      type = types.path;
      default = "/etc/nixos";
      description = "Path to the home-manager configuration.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      nos-update
      nos-upgrade
      nos-rebuild
    ];
  };
}
