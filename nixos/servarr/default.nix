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
      records), tries to port forward ports 80, 443, 50000 (rTorrent) using
      upnp and hosts the following services on localhost through a mullvad VPN:

      - Prowlarr
      - Sonarr
      - Radarr
      - Flood/Rtorrnet

      Note that Jellyfin is _not_ run through the VPN.

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
      type = types.nullOr types.str;
      default = null;
      description = "REQUIRED! The domain name to host jellyfin on.";
    };

    acmeMail = mkOption {
      type = types.nullOr types.str;
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
      type = types.str;
      default = "Etc/UTC";
      description = "Your timezone, used for logging purposes.";
    };

    upnp.enable = mkEnableOption "Enable automatic port forwarding using UPNP.";

    gluetun = {
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
    };
    rflood = {
      port = mkOption {
        type = types.port;
        default = 6001;
        description = "Port of rflood webui.";
      };

      peerTrafficPort = mkOption {
        type = types.port;
        default = 50000;
        description = "Rtorrent peer traffic port.";
      };

      dhtPort = mkOption {
        type = types.port;
        default = 6881;
        description = "Rtorrent dht port.";
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
      ulimits = {
        enable = mkEnableOption ''
          Enable rtorrent ulimits. I had a bug that caused rtorrent to fail
          and log `std::bad_alloc`. Setting ulimits for this service fixed
          the issue. You probably don't want to set this unless you have
          similar issues.See link below for more info:

          https://stackoverflow.com/questions/75536471/rtorrent-docker-container-failing-to-start-saying-stdbad-alloc
        '';
        hard = mkOption {
          type = types.ints.unsigned;
          default = 1024;
          description = "The hard limit.";
        };
        soft = mkOption {
          type = types.ints.unsigned;
          default = 1024;
          description = "The soft limit.";
        };
      };
    };
    prowlarr = {
      port = mkOption {
        type = types.port;
        default = 6002;
        description = "Port of prowlarr.";
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
    };
    sonarr = {
      port = mkOption {
        type = types.port;
        default = 6003;
        description = "Port of sonarr.";
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
    };
    radarr = {
      port = mkOption {
        type = types.port;
        default = 6004;
        description = "Port of radarr.";
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
    };
    jellyfin = {
      port = mkOption {
        type = types.port;
        default = 8096;
        description = "Port of Jellyfin.";
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra config for the service.";
      };
    };
  };

  config = let
    # Create a docker compose yaml-file from the nix attribute set below:
    servarr-config = yaml.generate "servarr.yaml" {
      secrets = { 
        openvpn_user.file = cfg.mullvadAcc;
      };
      services = {
        gluetun = cfg.gluetun.extraConfig // {
          image = "qmcgaw/gluetun";
          container_name = "gluetun";
          cap_add = ["NET_ADMIN"];
          devices = [ "/dev/net/tun:/dev/net/tun"];
          ports = [
            "8888:8888/tcp" # HTTP proxy
            "8388:8388/tcp" # Shadowsocks
            "8388:8388/udp" # Shadowsocks
            "${builtins.toString cfg.rflood.dhtPort}:6881"
            "${builtins.toString cfg.rflood.peerTrafficPort}:50000"
            "${builtins.toString cfg.rflood.port}:3000"
            "${builtins.toString cfg.prowlarr.port}:9696"
            "${builtins.toString cfg.sonarr.port}:8989"
            "${builtins.toString cfg.radarr.port}:7878"
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
        prowlarr = cfg.prowlarr.extraConfig // {
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
        rflood = cfg.rflood.extraConfig // {
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
          ulimits.nofile = if cfg.rflood.ulimits.enable then {
            hard = cfg.rflood.ulimits.hard;
            soft = cfg.rflood.ulimits.soft;
          } else {};
          volumes = [
            "${cfg.mediaDir}/torrents:/data/torrents"
            "${cfg.stateDir}/servarr/rflood:/config"
          ];
        };
        radarr = cfg.radarr.extraConfig // {
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
        sonarr = cfg.sonarr.extraConfig // {
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
        jellyfin = cfg.jellyfin.extraConfig // {
          container_name = "jellyfin";
          image = "ghcr.io/hotio/jellyfin";
          restart = "unless-stopped";
          ports = [ "${builtins.toString cfg.jellyfin.port}:8096" ];
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

    # UPNPC firewall access, if not set, then upnpc will fail with "No IGD
    # UPnP Device found !"
    #
    # Alternatively, I also tried allowing all traffic from the router. But
    # I assume that the official way is cleaner/more secure:
    # ```nix
    #   networking.firewall.extraCommands = ''
    #     iptables -I INPUT -p udp -s 192.168.1.1 -j ACCEPT
    #     iptables -I OUTPUT -p udp -d  192.168.1.1 -j ACCEPT
    #   '';
    # ```
    #
    # See:
    # https://github.com/miniupnp/miniupnp/blob/8ced59d384de13689d3b1c32405bcb562030b241/miniupnpc/README
    #
    # TODO: Understand this properly
    networking.firewall.extraCommands = ''
      # Rules for IPv4:
      ${pkgs.ipset}/bin/ipset create upnp hash:ip,port timeout 3
      iptables -A OUTPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j SET --add-set upnp src,src --exist
      iptables -A INPUT -p udp -m set --match-set upnp dst,dst -j ACCEPT
      iptables -A INPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j ACCEPT

      # Rules for IPv6:
      ${pkgs.ipset}/bin/ipset create upnp6 hash:ip,port timeout 3 family inet6
      ip6tables -A OUTPUT -d ff02::c/128 -p udp -m udp --dport 1900 -j SET --add-set upnp6 src,src --exist
      ip6tables -A OUTPUT -d ff05::c/128 -p udp -m udp --dport 1900 -j SET --add-set upnp6 src,src --exist
      ip6tables -A INPUT -p udp -m set --match-set upnp6 dst,dst -j ACCEPT
      ip6tables -A INPUT -d ff02::c/128 -p udp -m udp --dport 1900 -j ACCEPT
      ip6tables -A INPUT -d ff05::c/128 -p udp -m udp --dport 1900 -j ACCEPT
    '';

    # Create docker compose service for the servarr containers
    #
    # TODO: Split this into a UPNPC module that takes a list of tcp ports
    # and a list of udp ports and adds them to firewall and port forwards.
    systemd = {
      services = let 
        upnp-ports = pkgs.writeShellApplication {
          name = "upnp-ports";

          runtimeInputs = with pkgs; [miniupnpc];

          text = ''
            upnpc -r 80 TCP
            upnpc -r 80 UDP

            upnpc -r 443 TCP
            upnpc -r 443 UDP

            upnpc -r "${builtins.toString cfg.rflood.peerTrafficPort}" TCP
            upnpc -r "${builtins.toString cfg.rflood.peerTrafficPort}" UDP

            upnpc -r "${builtins.toString cfg.rflood.dhtPort}" TCP
            upnpc -r "${builtins.toString cfg.rflood.dhtPort}" UDP

            echo "Successfully requested upnp ports to be opened."
          '';
        };
      in {
        upnpc = mkIf cfg.upnp.enable {
          enable = true;
          description = "Sets port on router";
          script = "${upnp-ports}/bin/upnp-ports";

          serviceConfig = {
            User = "root";
            Type = "oneshot";
          };
        };

        servarr-docker-compose = {
          script = ''
            echo "Reading config: ${servarr-config}"
            ${pkgs.docker}/bin/docker container prune -f
            ${pkgs.docker-compose}/bin/docker-compose -f ${servarr-config} up --force-recreate --remove-orphans
          '';
          wantedBy = ["multi-user.target"];
          after = ["docker.service" "docker.socket"];
        };
      };

      timers = {
        upnpc = mkIf cfg.upnp.enable {
          description = "Sets port on router";
          wantedBy = ["timers.target"];

          timerConfig = {
            OnCalendar = "daily";
            Persistent = "true"; # Run service immediately if last window was missed
            RandomizedDelaySec = "1h"; # Run service OnCalendar +- 1h
          };
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 
      80 # http
      443 # https
      50000 # rTorrent
      6881 # rTorrent DHT
    ];

    networking.firewall.allowedUDPPorts = [ 
      50000 # rTorrent
      6881 # rTorrent DHT
    ];

    services.nginx = {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${builtins.replaceStrings ["\n"] [""] cfg.domainName}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${builtins.toString cfg.jellyfin.port}";
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeMail;
    };
  };
}
