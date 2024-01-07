# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.radarr;
in {
  options.kirk.servarr.radarr = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "Enable radarr";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/servarr/radarr";
      description = lib.mdDoc "The state directory for radarr";
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Use VPN with radarr";
    };
  };

  config = mkIf cfg.enable {
    services.radarr = {
      enable = cfg.enable;
      group = "media";
      dataDir = "${config.kirk.servarr.stateDir}/servarr/radarr";
    };

    kirk.vpnnamespace.portMappings = [(
      mkIf cfg.useVpn {
        From = 7878;
        To = 7878;
      }
    )];

    systemd.services.radarr = mkIf cfg.useVpn {
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
