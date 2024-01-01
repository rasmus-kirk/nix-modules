{ lib, pkgs, config, ... }: 
# Thanks to Maroka-chan...
# TODO: Make it so you can make multiple namespaces by giving a list of
# objects with settings as attributes. Also add an option to enable whether
# the namespace should use a vpn or not.
with lib;
let
  cfg = config.kirk.vpnnamespace;
in {
  options.kirk.vpnnamespace = {
    enable = mkEnableOption (lib.mdDoc "VPN Namespace") // {
      description = lib.mdDoc ''
        Whether to enable the VPN namespace.

        To access the namespace a veth pair is used to
        connect the vpn namespace and the default namespace
        through a linux bridge. One end of the pair is
        connected to the linux bridge on the default namespace.
        The other end is connected to the vpn namespace.

        Systemd services can be run within the namespace by
        adding these options:

        bindsTo = [ "netns@wg.service" ];
        requires = [ "network-online.target" ];
        after = [ "wg.service" ];
        serviceConfig = {
          NetworkNamespacePath = "/var/run/netns/wg";
        };
      '';
    };

    accessibleFrom = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = lib.mdDoc ''
        Subnets or specific addresses that the namespace should be accessible to.
      '';
      example = [
        "10.0.2.0/24"
        "192.168.1.27"
      ];
    };

    namespaceAddress = mkOption {
      type = types.str;
      default = "192.168.15.1";
      description = lib.mdDoc ''
        The address of the veth interface connected to the vpn namespace.
        
        This is the address used to reach the vpn namespace from other
        namespaces connected to the linux bridge.
      '';
    };

    bridgeAddress = mkOption {
      type = types.str;
      default = "192.168.15.5";
      description = lib.mdDoc ''
        The address of the linux bridge on the default namespace.

        The linux bridge sits on the default namespace and
        needs an address to make communication between the
        default namespace and other namespaces on the
        bridge possible.
      '';
    };

    wireguardAddressPath = mkOption {
      type = types.path;
      default = "";
      description = lib.mdDoc ''
        The address for the wireguard interface.
        It is a path to a file containing the address.
        This is done so the whole wireguard config can be specified
        in a secret file.
      '';
    };

    wireguardConfigFile = mkOption {
      type = types.path;
      default = "/etc/wireguard/wg0.conf";
      description = lib.mdDoc ''
        Path to the wireguard config to use.
        
        Note that this is not a wg-quick config.
      '';
    };

    portMappings = mkOption {
      type = with types; listOf (attrsOf port);
      default = [];
      description = lib.mdDoc ''
        A list of pairs mapping a port from the host to a port in the namespace.
      '';
      example = [{
        From = 80;
        To = 80;
      }];
    };

    dnsServer = mkOption {
      type = types.str;
      default = "1.1.1.2";
      description = lib.mdDoc ''
        YOUR VPN WILL LEAK IF THIS IS NOT SET. The dns address of your vpn
      '';
      example = "1.1.1.2";
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
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    systemd.services."netns@" = {
      description = "%I network namespace";
      before = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add %I";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del %I";
      };
    };

    systemd.services = {
      wg = {
        description = "wg network interface";
        bindsTo = [ "netns@wg.service" ];
        requires = [ "network-online.target" ];
        after = [ "netns@wg.service" ];
        wantedBy = [ "netns@wg.service" ];

        serviceConfig = let 
          vpn-namespace = pkgs.writeShellApplication {
            name = "vpn-namespace";

            runtimeInputs = with pkgs; [ iproute2 wireguard-tools iptables ];

            text = ''
              echo "$PWD"
              # Set up the wireguard interface
              tmpdir=$(mktemp -d) 
              cat ${cfg.wireguardConfigFile} > "$tmpdir/wg.conf"
            
              ip link add wg0 type wireguard
              ip link set wg0 netns wg
              ip -n wg address add "$(cat ${cfg.wireguardAddressPath})" dev wg0
              ip netns exec wg wg setconf wg0 <(wg-quick strip "$tmpdir/wg.conf")
              ip -n wg link set wg0 up
              ip -n wg route add default dev wg0

              # Start the loopback interface
              ip -n wg link set dev lo up

              # Create a bridge
              ip link add v-net-0 type bridge
              ip addr add ${cfg.bridgeAddress}/24 dev v-net-0
              ip link set dev v-net-0 up

              # Set up veth pair to link namespace with host network
              ip link add veth-vpn-br type veth peer name veth-vpn netns wg
              ip link set veth-vpn-br master v-net-0

              ip -n wg addr add ${cfg.namespaceAddress}/24 dev veth-vpn
              ip -n wg link set dev veth-vpn up

              mkdir -p /etc/netns/wg/ && echo "nameserver ${cfg.dnsServer}" > /etc/netns/wg/resolv.conf

              #iptables -A INPUT -p tcp --dport 33915 -j ACCEPT
              #iptables -A INPUT -p udp --dport 33915 -j ACCEPT
              #iptables -A INPUT -dport 33915 -j ACCEPT
              #iptables -I INPUT -j LOG 

              #ip netns exec wg iptables -I INPUT -p tcp --dport 33915 -j ACCEPT
            ''

            # Add routes to make the namespace accessible
            + strings.concatMapStrings (x: 
              "ip -n wg route add ${x} via ${cfg.bridgeAddress}" + "\n"
            ) cfg.accessibleFrom

            # Add prerouting rules
            + strings.concatMapStrings (x: 
              "ip netns exec wg iptables -t nat -A PREROUTING -p tcp --dport ${builtins.toString x.From} -j DNAT --to-destination ${cfg.namespaceAddress}:${builtins.toString x.To}" +
              "\n"
            ) cfg.portMappings

            # Allow VPN TCP ports
            + strings.concatMapStrings (x: 
              "ip netns exec wg iptables -I INPUT -p tcp --dport ${builtins.toString x} -j ACCEPT" +
              "\n"
            ) cfg.openTcpPorts

            # Allow VPN UDP ports
            + strings.concatMapStrings (x: 
              "iptables -I INPUT -p udp --dport ${builtins.toString x} -j ACCEPT" +
              "\n"
            ) cfg.openUdpPorts;
          };
        in {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${vpn-namespace}/bin/vpn-namespace";

          ExecStopPost = with pkgs; writers.writeBash "wg-down" (''
            ${iproute2}/bin/ip -n wg route del default dev wg0
            ${iproute2}/bin/ip -n wg link del wg0
            ${iproute2}/bin/ip -n wg link del veth-vpn
            ${iproute2}/bin/ip link del v-net-0
          ''

          # Delete prerouting rules
          + strings.concatMapStrings (x: "${iptables}/bin/iptables -t nat -D PREROUTING -p tcp --dport ${builtins.toString x.From} -j DNAT --to-destination ${cfg.namespaceAddress}:${builtins.toString x.To}" + "\n") cfg.portMappings);
        };
      };
    };

    systemd.services.vpn-test-service = mkIf (cfg.vpnTestService.enable && cfg.enable) {
      script = let
        vpn-test = pkgs.writeShellApplication {
          name = "vpn-test";

          runtimeInputs = with pkgs; [ unixtools.ping coreutils curl bash libressl netcat-gnu openresolv ];

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

            # DNS leak test
            curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
            chmod +x dnsleaktest.sh
            ./dnsleaktest.sh

            echo "starting netcat on port ${builtins.toString cfg.vpnTestService.port}:"
            nc -vnlp ${builtins.toString cfg.vpnTestService.port}
          '';
        };
      in "${vpn-test}/bin/vpn-test";

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
  };
}
