{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.homeManagerScripts;
  configDir = if (cfg.configDir != null) then cfg.configDir else "${config.xdg.configHome}/home-manager";

  hm-clean = pkgs.writeShellApplication {
    name = "hm-clean";
    text = ''
      # Delete old home-manager profiles
      home-manager expire-generations '-30 days' &&
      # Delete old nix profiles
      nix profile wipe-history --older-than 30d &&
      # Optimize space
      nix store gc &&
      nix store optimise
    '';
  };

  hm-update = pkgs.writeShellApplication {
    name = "hm-update";
    text = ''
      nix flake update ${configDir}
    '';
  };

  hm-upgrade = pkgs.writeShellApplication {
    name = "hm-upgrade";
    text = ''
      # Update, switch to new config, and cleanup
      ${hm-update}/bin/hm-update &&
      ${hm-rebuild}/bin/hm-rebuild &&
      ${hm-clean}/bin/hm-clean
    '';
  };

  hm-rebuild = pkgs.writeShellApplication {
    name = "hm-rebuild";
    text = ''
      home-manager switch -b backup --flake ${configDir}#${cfg.machine}
    '';
  };
in {
  options.kirk.homeManagerScripts = {
    enable = mkEnableOption "home manager scripts";

    configDir = mkOption {
      type = types.nullOr types.path;
      # modules are evaluated as follows: imports, options, config
      # you don't want to refer to config. from options as they haven't been evaluated yet.
      default = null;
      description = "Path to the home-manager configuration.";
    };

    machine = mkOption {
      type = types.nullOr types.str;
      description = "Path to the home-manager configuration.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.machine != null;
        message = "Machine value must be set!";
      }
    ];

    home.packages = [
      hm-update
      hm-upgrade
      hm-rebuild
      hm-clean
    ];
  };
}
