# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr;
in {
  imports = [
    ./jellyfin
    ./radarr
    ./sonarr
    ./prowlarr
    ./transmission
  ];
  
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

    mediaUsers = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Extra users to add the the media group, giving access to the media directory. You probably want to add your own user here.";
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

    upnp.enable = mkEnableOption "Enable automatic port forwarding using UPNP.";

    vpn = {
      enable = mkEnableOption ''enable vpn'';

      wgConf = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "REQUIRED! The path to the wireguard configuration file.";
      };

      wgAddress = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "REQUIRED! wg address.";
      };

      dnsServer = mkOption {
        type = types.str;
        default = "1.1.1.2";
        description = lib.mdDoc ''
          YOUR VPN WILL LEAK IF THIS IS NOT SET. The dns address of your vpn
        '';
        example = "1.1.1.2";
      };

      vpnTestService = {
        enable = mkEnableOption "Enable the vpn test service.";
        port = mkOption {
          type = types.port;
          default = [ 12300 ];
          description = lib.mdDoc ''
            The port that the vpn test service listens to.
          '';
          example = [ 58403 ];
        };
      };

      openTcpPorts = mkOption {
        type = with types; listOf port;
        default = [];
        description = lib.mdDoc ''
          What TCP ports to allow incoming traffic from. You need this if
          you're port forwarding on your VPN provider.
        '';
        example = [ 46382 38473 ];
      };

      openUdpPorts = mkOption {
        type = with types; listOf port;
        default = [];
        description = lib.mdDoc ''
          What UDP ports to allow incoming traffic from. You need this if
          you're port forwarding on your VPN provider.
        '';
        example = [ 46382 38473 ];
      };
    };
  };

  config = mkIf cfg.enable {
    users.groups = {
      media = {
        members = cfg.mediaUsers;
        gid = 992;
      };
      prowlarr = {};
      transmission = {};
      jellyfin = {};
    };
    users.users = {
      jellyfin = {
        isSystemUser = true;
        uid = lib.mkForce 994;
      };
      sonarr = {
        isSystemUser = true;
        group = "media";
        uid = lib.mkForce 991;
      };
      radarr = {
        isSystemUser = true;
        group = "media";
        uid = lib.mkForce 275;
      };
      transmission = {
        isSystemUser = true;
        group = "transmission";
        uid = lib.mkForce 990;
      };
      prowlarr = {
        isSystemUser = true;
        group = "prowlarr";
        uid = lib.mkForce 989;
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'                      0755 root         root  - -"
      "d '${cfg.stateDir}/servarr'              0755 root         root  - -"
      "d '${cfg.stateDir}/servarr/jellyfin'     0700 jellyfin     root  - -"
      "d '${cfg.stateDir}/servarr/transmission' 0700 transmission root  - -"
      "d '${cfg.stateDir}/servarr/sonarr'       0700 sonarr       root  - -"
      "d '${cfg.stateDir}/servarr/radarr'       0700 radarr       root  - -"
      "d '${cfg.stateDir}/servarr/prowlarr'     0700 prowlarr     root  - -"

      "d '${cfg.mediaDir}'                      0775 root         media - -"
      "d '${cfg.mediaDir}/library'              0775 jellyfin     media - -"
      "d '${cfg.mediaDir}/library/series'       0775 jellyfin     media - -"
      "d '${cfg.mediaDir}/library/movies'       0775 jellyfin     media - -"
      "d '${cfg.mediaDir}/torrents'             0755 transmission media - -"
      "d '${cfg.mediaDir}/torrents/.incomplete' 0755 transmission media - -"
      "d '${cfg.mediaDir}/torrents/.watch'      0755 transmission media - -"
    ];

    kirk.upnp.enable = cfg.upnp.enable;

    kirk.vpnnamespace = {
      enable = true;
      accessibleFrom = [
        "192.168.1.0/24"
        "127.0.0.1"
      ];
      dnsServer = cfg.vpn.dnsServer;
      wireguardAddressPath = cfg.vpn.wgAddress;
      wireguardConfigFile = cfg.vpn.wgConf;
      vpnTestService = {
        enable = cfg.vpn.vpnTestService.enable;
        port = cfg.vpn.vpnTestService.port;
      };
      openTcpPorts = cfg.vpn.openTcpPorts;
      openUdpPorts = cfg.vpn.openUdpPorts;
    };
  };
}
