# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.sonarr;
  defaultPort = 8989;
  servarr = config.kirk.servarr;
  dnsServers = config.kirk.vpnnamespace.dnsServers;
in {
  options.kirk.servarr.sonarr = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "Enable sonarr";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${servarr.stateDir}/sonarr";
      description = lib.mdDoc "The state directory for sonarr";
    };

    useVpn = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc "Use VPN with sonarr";
    };
  };

  config = mkIf cfg.enable {
    services.sonarr = mkIf (!cfg.useVpn) {
      enable = cfg.enable;
      user = "sonarr";
      group = "media";
      dataDir = "${config.kirk.servarr.stateDir}/servarr/sonarr";
    };

    kirk.vpnnamespace.portMappings = [
      (mkIf cfg.useVpn {
        From = defaultPort;
        To = defaultPort;
      })
    ];

    containers.sonarr = mkIf cfg.useVpn {
      autoStart = true;
      ephemeral = true;
      extraFlags = [ "--network-namespace-path=/var/run/netns/wg" ];

      bindMounts = {
        "${servarr.mediaDir}".isReadOnly = false;
        "${config.kirk.servarr.stateDir}/servarr/sonarr".isReadOnly = false;
      };

      config = {
        # Use systemd-resolved inside the container
        # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.nameservers = dnsServers;

        users.groups.media = {};

        services.sonarr = {
          enable = cfg.enable;
          group = "media";
          dataDir = "${servarr.stateDir}/servarr/sonarr";
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
