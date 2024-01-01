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
    ./rtorrent
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
    users.groups.media = {};
    users.users = {
      media = {
        isSystemUser = true;
        group = "media";
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'                  0750 media    media - -"
      "d '${cfg.stateDir}/servarr/jellyfin' 0750 jellyfin media - -"
      "d '${cfg.stateDir}/servarr/rtorrent' 0750 rtorrent media - -"
      "d '${cfg.stateDir}/servarr/sonarr'   0750 sonarr   media - -"
      "d '${cfg.stateDir}/servarr/radarr'   0750 radarr   media - -"

      "d '${cfg.mediaDir}'                  0750 media    media - -"
      "d '${cfg.mediaDir}/library'          0750 jellyfin media - -"
      "d '${cfg.mediaDir}/library/series'   0750 jellyfin media - -"
      "d '${cfg.mediaDir}/library/movies'   0750 jellyfin media - -"
      "d '${cfg.mediaDir}/torrents'         0750 rtorrent media - -"
    ];

    kirk.upnp = {
      enable = cfg.upnp.enable;
      openUdpPorts = [
        cfg.jellyfin.port
        cfg.sonarr.port
        cfg.radarr.port
        cfg.prowlarr.port
        cfg.rtorrent.port
      ];
      openTcpPorts = [
        cfg.rtorrent.port
      ];
    };

    kirk.vpnnamespace = {
      enable = true;
      accessibleFrom = [
        "192.168.0.0/24"
      ];
      dnsServer = cfg.vpn.dnsServer;
      wireguardAddressPath = cfg.vpn.wgAddress;
      wireguardConfigFile = cfg.vpn.wgConf;
      vpnTestService = {
        enable = cfg.vpn.vpnTestService.enable;
        port = cfg.vpn.port;
      };
      openTcpPorts = cfg.vpn.openTcpPorts;
      openUdpPorts = cfg.vpn.openUdpPorts;
    };
  };
}
