# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.sonarr;
in {
  options.kirk.servarr.sonarr = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "Enable sonarr";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/sonarr";
      description = lib.mdDoc "The state directory for sonarr";
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Use VPN with sonarr";
    };
  };

  config = mkIf cfg.enable {
    services.sonarr = {
      enable = cfg.enable;
      group = "media";
      dataDir = "${cfg.stateDir}/servarr/sonarr";
    };

    kirk.vpnnamespace.portMappings = [
      (mkIf cfg.enableVpn {
        From = cfg.port;
        To = cfg.port;
      })
    ];

    systemd.services.sonarr = mkIf cfg.useVpn {
      bindsTo = [ "netns@wg.service" ];
      requires = [ "network-online.target" ];
      after = [ "wg.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/var/run/netns/wg";
        BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
      };
    };
  };
}
