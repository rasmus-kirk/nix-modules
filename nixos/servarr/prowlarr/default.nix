# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.prowlarr;
in {
  options.kirk.servarr.prowlarr = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "Enable prowlarr";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/servarr/prowlarr";
      description = lib.mdDoc "The state directory for prowlarr";
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Use VPN with prowlarr";
    };
  };

  config = mkIf cfg.enable {
    services.prowlarr = {
      enable = cfg.enable;
      openFirewall = true;
    };

    kirk.vpnnamespace.portMappings = [(
      mkIf cfg.useVpn {
        From = 9696;
        To = 9696;
      }
    )];

    systemd.services.prowlarr = mkIf cfg.useVpn {
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
