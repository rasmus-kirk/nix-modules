# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  defaultPort = 9696;
  dnsServers = config.kirk.vpnnamespace.dnsServer;
  servarr = config.kirk.servarr;
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
      default = "${servarr.stateDir}/servarr/prowlarr";
      description = lib.mdDoc "The state directory for prowlarr.";
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Use VPN with prowlarr";
    };
  };

  config = mkIf cfg.enable {
    services.prowlarr = mkIf (!cfg.useVpn) {
      enable = true;
      openFirewall = true;
    };
  
    kirk.vpnnamespace.portMappings = [(
      mkIf cfg.useVpn {
        From = defaultPort;
        To = defaultPort;
      }
    )];

    containers.prowlarr = mkIf cfg.useVpn {
      autoStart = true;
      ephemeral = true;
      extraFlags = if cfg.useVpn then 
        [ "--network-namespace-path=/var/run/netns/wg" ]
      else [];

      bindMounts = {
        "/var/lib/prowlarr" = {
          hostPath = cfg.stateDir;
          isReadOnly = false;
        };
      };

      config = {
        # Use systemd-resolved inside the container
        # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.nameservers = dnsServers;

        users.groups.prowlarr = {};
        users.users.prowlarr = {
          isSystemUser = true;
          group = "prowlarr";
        };

        services.prowlarr = {
          enable = true;
          openFirewall = true;
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
