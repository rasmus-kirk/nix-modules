# TODO: Dir creation and file permissions in nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.transmission;
  servarr = config.kirk.servarr;
  write-secrets = pkgs.writeShellApplication {
    name = "write-secrets";

    runtimeInputs = with pkgs; [ util-linux unixtools.ping coreutils curl jq ];

    text = ''
      mkdir -pm 0770 /var/lib/secrets/transmission
      cd /var/lib/secrets/transmission
      touch config.json
      chmod 0770 config.json
      echo '{ "rpc-password": "test-password" }' > config.json
    '';
  };

in {
  imports = [
    ./flood-module
  ];

  options.kirk.servarr.transmission = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "enable transmission";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${servarr.stateDir}/servarr/transmission";
      description = lib.mdDoc "The state directory for transmission";
    };

    downloadDir = mkOption {
      type = types.path;
      default = "${servarr.mediaDir}/torrents";
      description = lib.mdDoc ''
        The directory for transmission to download to.
      '';
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Run transmission through VPN";
    };

    port = mkOption {
      type = types.port;
      default = 50000;
      description = "transmission peer traffic port.";
    };

    dhtPort = mkOption {
      type = types.port;
      default = 6881;
      description = "transmission dht port.";
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Extra config for the service.";
    };

    flood = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = lib.mdDoc "Enable the flood web UI";
      };

      useVpn = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc "Run Flood through VPN";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = lib.mdDoc ''
          The port that Flood should listen for web connections on.
        '';
      };

      stateDir = mkOption {
        type = types.path;
        default = "${servarr.stateDir}/servarr/flood";
        description = lib.mdDoc ''
          The directory for flood to keep its state in.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    kirk.vpnnamespace = {
      portMappings = [
        (mkIf cfg.flood.useVpn {
          From = cfg.flood.port;
          To = cfg.flood.port;
        }) {
          From = 9091;
          To = 9091;
        }
      ];
      openUdpPorts = [ cfg.port ];
      openTcpPorts = [ cfg.port ];
    };

    systemd.services = { 
      transmission =  mkIf cfg.useVpn {
        bindsTo = [ "netns@wg.service" ];
        requires = [ "network-online.target" ];
        after = [ "wg.service" ];
        serviceConfig = {
          NetworkNamespacePath = "/var/run/netns/wg";
          #BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
        };
      };

      flood = mkIf cfg.flood.useVpn {
        bindsTo = [ "netns@wg.service" ];
        requires = [ "network-online.target" ];
        after = [ "wg.service" ];
        serviceConfig = {
          NetworkNamespacePath = "/var/run/netns/wg";
          #BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
        };
      };
    };

    services.transmission = {
      enable = cfg.enable;
      #home = cfg.stateDir;
      webHome = pkgs.flood-for-transmission;
      settings = {
        downloadDir = "${servarr.mediaDir}/torrents";
        incomplete-dir = "${servarr.mediaDir}/torrents/.incomplete";
        incomplete-dir-enabled = true;
        watch-dir = "${servarr.mediaDir}/torrents/.watch";
        watch-dir-enabled = true;
        peer-port = cfg.port;
        port-forwarding-enabled = false;
        credentialsFile = "/var/lib/secrets/transmission/config.json";
        rpc-username = "transmission";
        rpc-host-whitelist-enabled = false;
      } // cfg.extraConfig;
      openFirewall = false;
    };

    services.flood = {
      enable = cfg.flood.enable;
      port = cfg.flood.port;
      group = config.services.transmission.group;
      openFirewall = false;
      auth.transmission = {
        url = "http://"
            + config.services.transmission.settings.rpc-bind-address
            + ":"
            + builtins.toString config.services.transmission.settings.rpc-port
            + "/transmission/";
        user = "transmission";
        pass = "test-password";
      };
    };

    networking.firewall.allowedTCPPorts = [ 
      cfg.port # rTorrent
      cfg.dhtPort # rTorrent DHT
    ];

    networking.firewall.allowedUDPPorts = [ 
      cfg.port # rTorrent
      cfg.dhtPort # rTorrent DHT
    ];
  };
}
