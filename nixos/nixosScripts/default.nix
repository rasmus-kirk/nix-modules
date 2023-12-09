{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.nixosScripts;

  nos-update = pkgs.writeShellApplication {
    name = "nos-update";
    text = ''
      nix flake update ${cfg.configDir}
    '';
  };

  nos-upgrade = pkgs.writeShellApplication {
    name = "nos-upgrade";
    text = ''
      # Update, switch to new config, and cleanup
      ${nos-update}/bin/hm-update &&
      ${nos-rebuild}/bin/hm-rebuild &&
    '';
  };

  nos-rebuild = pkgs.writeShellApplication {
    name = "nos-rebuild";
    text = ''
      # Update the inputs of this repo on every rebuild
      nix flake lock --update-input kirk-modules ${cfg.onfigDir} &&
      # Switch configuration, backing up files
      nixos-rebuild switch --flake ${cfg.configDir}#${cfg.machine} &&
      hm-upgrade || echo "Couldn't run home-manager upgrade script!"
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
      description = "Path to the nixos configuration.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      nos-update
      nos-upgrade
      nos-rebuild
    ];
  };
}
