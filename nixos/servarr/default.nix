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
      "d '${cfg.stateDir}'                      0755 root         root  - -"
      "d '${cfg.stateDir}/servarr'              0755 root         root  - -"
      "d '${cfg.stateDir}/servarr/jellyfin'     0700 jellyfin     media - -"
      "d '${cfg.stateDir}/servarr/transmission' 0700 transmission media - -"
      "d '${cfg.stateDir}/servarr/sonarr'       0700 sonarr       media - -"
      "d '${cfg.stateDir}/servarr/radarr'       0700 radarr       media - -"

      "d '${cfg.mediaDir}'                      0755 root         root  - -"
      "d '${cfg.mediaDir}/library'              0750 jellyfin     media - -"
      "d '${cfg.mediaDir}/library/series'       0750 jellyfin     media - -"
      "d '${cfg.mediaDir}/library/movies'       0750 jellyfin     media - -"
      "d '${cfg.mediaDir}/torrents'             0750 transmission media - -"
      "d '${cfg.mediaDir}/torrents/.incomplete' 0750 transmission media - -"
      "d '${cfg.mediaDir}/torrents/.watch'      0750 transmission media - -"
    ];

    #kirk.upnp = {
    #  enable = cfg.upnp.enable;
    #  openUdpPorts = [
    #    cfg.jellyfin.port
    #    cfg.sonarr.port
    #    cfg.radarr.port
    #    cfg.prowlarr.port
    #    cfg.rtorrent.port
    #  ];
    #  openTcpPorts = [
    #    cfg.rtorrent.port
    #  ];
    #};
    systemd.services.vpn-test-service = {
      script = let
        vpn-test = pkgs.writeShellApplication {
          name = "vpn-test";

          runtimeInputs = with pkgs; [ unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];

          text = ''
            cd "$(mktemp -d)"

            # Print resolv.conf
            echo "/etc/resolv.conf contains:"
            cat /etc/resolv.conf
            echo ""

            # Query resolvconf
            echo "resolvconf output:"
            resolvconf -l
            echo ""

            # Get ip
            curl -s ipinfo.io

            echo -ne "Making DNS requests... "
            # shellcheck disable=SC2034
            DATA=$(for i in {1..10}; do dig "$RANDOM.go.dnscheck.tools" TXT +short | grep -e remoteIP -e remoteNetwork | sort; done)
            echo -ne "done\n\n"
            echo -ne "Summary of your DNS resolvers:\n\n"
            echo "$DATA" | sort | uniq -c | sort -nr | sed -e 's/"//g' -e 's/remoteIP:/|/' -e 's/remoteNetwork:/|/' | column -t -s '|'

            # DNS leak test
            curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
            chmod +x dnsleaktest.sh
            ./dnsleaktest.sh

            echo "starting netcat on port ${builtins.toString cfg.vpn.vpnTestService.port}:"
            nc -vnlp ${builtins.toString cfg.vpn.vpnTestService.port}
          '';
        };
        vpn-test-wrapped = pkgs.writeShellApplication {
          name = "vpn-test-wrapped";

          runtimeInputs = with pkgs; [ bubblewrap ];

          text = ''
            set -euo pipefail
            (exec bwrap --ro-bind /usr /usr \
                  --dir /tmp \
                  --dir /var \
                  --symlink ../tmp var/tmp \
                  --proc /proc \
                  --dev /dev \
                  --ro-bind ./resolv.conf /etc/resolv.conf \
                  --ro-bind ./test2.bash /test2.bash \
                  --ro-bind /nix/store /nix/store \
                  --ro-bind /dnsleaktest.sh /dnsleaktest.sh \
                  --ro-bind /run/current-system/sw /run/current-system/sw \
                  --ro-bind /etc/ssl /etc/ssl \
                  --symlink usr/lib /lib \
                  --symlink usr/lib64 /lib64 \
                  --symlink usr/bin /bin \
                  --symlink usr/sbin /sbin \
                  --chdir / \
                  --unshare-all \
                  --share-net \
                  --die-with-parent \
                  --dir /run/user/"$(id -u)" \
                  --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" \
                  --setenv PS1 "bwrap-demo$ " \
                  --setenv PATH "$PATH" \
                  --file 11 /etc/passwd \
                  --file 12 /etc/group \
                  ${vpn-test}/bin/vpn-test) \
                11< <(getent passwd $UID 65534) \
                12< <(getent group "$(id -g)" 65534)
          '';
        };
      in "${vpn-test-wrapped}/bin/vpn-test-wrapped";

      bindsTo = [ "netns@wg.service" ];
      requires = [ "network-online.target" ];
      after = [ "wg.service" ];
      serviceConfig = {
        #User = "media";
        #Group = "media";
        NetworkNamespacePath = "/var/run/netns/wg";
        BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
      };
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
        port = cfg.vpn.vpnTestService.port;
      };
      openTcpPorts = cfg.vpn.openTcpPorts;
      openUdpPorts = cfg.vpn.openUdpPorts;
    };
  };
}
