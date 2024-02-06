# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.radarr;
  defaultPort = 7878;
  servarr = config.kirk.servarr;
  dnsServer = config.kirk.vpnnamespace.dnsServer;
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
    services.radarr = mkIf (!cfg.useVpn) {
      enable = cfg.enable;
      user = "radarr";
      group = "media";
      dataDir = "${config.kirk.servarr.stateDir}/servarr/radarr";
    };

    kirk.vpnnamespace.portMappings = [(
      mkIf cfg.useVpn {
        From = defaultPort;
        To = defaultPort;
      }
    )];

    containers.radarr= mkIf cfg.useVpn {
      autoStart = true;
      ephemeral = true;
      extraFlags = [ "--network-namespace-path=/var/run/netns/wg" ];

      bindMounts = {
        "${servarr.mediaDir}".isReadOnly = false;
        "${config.kirk.servarr.stateDir}/servarr/radarr".isReadOnly = false;
      };

      config = {
        # Use systemd-resolved inside the container
        # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.nameservers = [ dnsServer ];

        users.groups.media = {};

        services.radarr = {
          enable = true;
          group = "media";
          dataDir = "${config.kirk.servarr.stateDir}/servarr/radarr";
        };

        system.stateVersion = "23.11";
      };
    };

    services.nginx = mkIf cfg.useVpn {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString defaultPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = defaultPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString defaultPort}";
        };
      };
    };

  };
}
