# TODO: Dir creation and file permissions in nix
# TODO: Port configuration
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
cfg = config.kirk.servarr;
yaml = pkgs.formats.yaml {};
in {
  options.kirk.servarr = {
    enable = mkEnableOption ''
      My servarr setup. Hosts Jellyfin on the given domain (remember domain
      records/port forwarding) and hosts the following services on localhost
      through a mullvad VPN:

      - Prowlarr
      - Sonarr
      - Radarr
      - Flood/Rtorrnet

      Required options for this module:

      - `domainName`
      - `acmeMail`
      - `mullvadAcc`

      Remember to read the options.

      NOTE: The docker service to manage this executes the command `docker
      container prune -f` on startup for reproducibility, may cause issues
      depending on your setup.

      NOTE: This nixos module only supports the mullvad VPN, if you need
      another VPN, create a PR or fork this repo!
    '';

    domainName = mkOption {
      type = types.nullOr types.string;
      default = null;
      description = "REQUIRED! The domain name to host jellyfin on.";
    };

    acmeMail = mkOption {
      type = types.nullOr types.string;
      default = null;
      description = "REQUIRED! The ACME mail.";
    };

    mullvadAcc = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "REQUIRED! The location the file containing your mullvad account key.";
    };

    mediaDir = mkOption {
      type = types.path;
      default = "~/servarr";
      description = "The location of the media directory for the services.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "~/.local/state";
      description = "The location of the state directory for the services.";
    };

    timezone = mkOption {
      type = types.string;
      default = "Etc/UTC";
      description = "Your timezone, used for logging purposes.";
    };

    rtorrentLimits = {
      enable = mkEnableOption "Enable rtorrent limits.";
    };
  };

  config = let
    # Create a docker compose yaml-file from the nix attribute set below:
    servarr-config = yaml.generate "servarr.yaml" {
      secrets = { 
        openvpn_user.file = cfg.mullvadAcc;
      };
      services = {
        gluetun = {
          image = "qmcgaw/gluetun";
          container_name = "gluetun";
          cap_add = ["NET_ADMIN"];
          devices = [ "/dev/net/tun:/dev/net/tun"];
          ports = [
            "8888:8888/tcp" # HTTP proxy
            "8388:8388/tcp" # Shadowsocks
            "8388:8388/udp" # Shadowsocks
            "6002:3000" # rflood
            "6003:9696" # prowlarr
            "6004:8989" # sonarr
            "6005:7878" # radarr
          ];
          volumes = [ "/data/.state/servarr/gluetun:/gluetun" ];
          secrets = [ "openvpn_user" ];
          environment = [
            "VPN_SERVICE_PROVIDER=mullvad"
            "VPN_TYPE=openvpn"
            "OPENVPN_USER=/run/secrets/openvpn_user"
            "TZ=${cfg.timezone}"
            "UPDATER_PERIOD=24h"
          ];
        };
        prowlarr = {
          container_name = "prowlarr";
          image = "ghcr.io/hotio/prowlarr";
          restart = "unless-stopped";
          network_mode = "service:gluetun";
          environment = [
            "PUID=1000"
            "PGID=1000"
            "UMASK=002"
            "TZ=${cfg.timezone}"
          ];
          volumes = [ "${cfg.stateDir}/servarr/prowlarr:/config" ];
        };
        rflood = {
          container_name = "rflood";
          image = "ghcr.io/hotio/rflood";
          restart = "unless-stopped";
          network_mode = "service:gluetun";
          environment = [
            "PUID=1000"
            "PGID=1000"
            "UMASK=002"
            "TZ=${cfg.timezone}"
            "FLOOD_AUTH=false"
          ];
          ulimits.nofile = {
            hard = 1024;
            soft = 1024;
          };
          volumes = [
            "${cfg.mediaDir}/torrents:/data/torrents"
            "${cfg.stateDir}/servarr/rflood:/config"
          ];
        };
        radarr = {
          container_name = "radarr";
          image = "ghcr.io/hotio/radarr";
          restart = "unless-stopped";
          network_mode = "service:gluetun";
          environment = [
            "PUID=1000"
            "PGID=1000"
            "UMASK=002"
            "TZ=${cfg.timezone}"
          ];
          volumes = [
            "${cfg.mediaDir}:/data"
            "${cfg.stateDir}/servarr/radarr:/config"
          ];
        };
        sonarr = {
          container_name = "sonarr";
          image = "ghcr.io/hotio/sonarr";
          restart = "unless-stopped";
          network_mode = "service:gluetun";
          environment = [
            "PUID=1000"
            "PGID=1000"
            "UMASK=002"
            "TZ=${cfg.timezone}"
          ];
          volumes = [
            "${cfg.mediaDir}:/data"
            "${cfg.stateDir}/servarr/sonarr:/config"
          ];
        };
        jellyfin = {
          container_name = "jellyfin";
          image = "ghcr.io/hotio/jellyfin";
          restart = "unless-stopped";
          ports = [ "8096:8096" ];
          environment = [
            "PUID=1000"
            "PGID=1000"
            "UMASK=002"
            "TZ=${cfg.timezone}"
          ];
          volumes = [
            "${cfg.mediaDir}/library:/data/library"
            "${cfg.stateDir}/servarr/jellyfin:/config"
          ];
        };
      };
    }; 
  in mkIf cfg.enable {
    # Install docker
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
      extraPackages = [ pkgs.docker-compose ];
    };
    # Create docker compose service for the servarr containers
    systemd.services.servarr-docker-compose = {
      script = ''
        echo "Reading config: ${servarr-config}"
        ${pkgs.docker}/bin/docker container prune -f
        ${pkgs.docker-compose}/bin/docker-compose -f ${servarr-config} up --force-recreate --remove-orphans
      '';
      wantedBy = ["multi-user.target"];
      after = ["docker.service" "docker.socket"];
    };

    # Not sure if this is necessary, `services.nginx` may do it by default
    networking.firewall.allowedTCPPorts = [ 80 443 ];
    services.nginx = {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${cfg.domainName}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:8096";
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeMail;
    };
  };
}
