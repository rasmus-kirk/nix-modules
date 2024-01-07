# TODO: Dir creation and file permissions in nix
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.rtorrent;
  defaultConfig = ''
    #############################################################################
    # A minimal rTorrent configuration that provides the basic features
    # you want to have in addition to the built-in defaults.
    #
    # See https://github.com/rakshasa/rtorrent/wiki/CONFIG-Template
    # for an up-to-date version.
    #############################################################################

    ## Instance layout (base paths)
    method.insert = cfg.basedir,  private|const|string, (cat,"${cfg.stateDir}")
    method.insert = cfg.download, private|const|string, (cat,"${cfg.downloadDir}")
    method.insert = cfg.logs,     private|const|string, (cat,(cfg.basedir),"log/")
    method.insert = cfg.logfile,  private|const|string, (cat,(cfg.logs),"rtorrent-",(system.time),".log")
    method.insert = cfg.session,  private|const|string, (cat,(cfg.basedir),"session/")
    method.insert = cfg.watch,    private|const|string, (cat,(cfg.basedir),"watch/")


    ## Create instance directories
    execute.throw = sh, -c, (cat,\
        "mkdir -p \"",(cfg.download),"\" ",\
        "\"",(cfg.logs),"\" ",\
        "\"",(cfg.session),"\" ",\
        "\"",(cfg.watch),"/load\" ",\
        "\"",(cfg.watch),"/start\" ")


    ## Listening port for incoming peer traffic (fixed; you can also randomize it)
    network.port_range.set = ${cfg.port}-${cfg.port}
    network.port_random.set = no


    ## Tracker-less torrent and UDP tracker support
  '' ++ (if cfg.usePublicTrackers then ''
    dht.mode.set = auto
    dht.port.set = ${cfg.dhtPort}
    protocol.pex.set = 1
    trackers.use_udp.set = 1

    # Adding public DHT servers for easy bootstrapping
    schedule2 = dht_node_1, 5, 0, "dht.add_node=router.utorrent.com:6881"
    schedule2 = dht_node_2, 5, 0, "dht.add_node=dht.transmissionbt.com:6881"
    schedule2 = dht_node_3, 5, 0, "dht.add_node=router.bitcomet.com:6881"
    schedule2 = dht_node_4, 5, 0, "dht.add_node=dht.aelitis.com:6881"
  '' else ''
    ## (conservative settings for 'private' trackers, change for 'public')
    dht.mode.set = disable
    protocol.pex.set = no
    trackers.use_udp.set = no
  '') ++ ''
    ## Peer settings
    throttle.max_uploads.set = 100
    throttle.max_uploads.global.set = 250

    throttle.min_peers.normal.set = 20
    throttle.max_peers.normal.set = 60
    throttle.min_peers.seed.set = 30
    throttle.max_peers.seed.set = 80
    trackers.numwant.set = 80

    protocol.encryption.set = allow_incoming,try_outgoing,enable_retry

    ## Limits for file handle resources, this is optimized for
    ## an `ulimit` of 1024 (a common default). You MUST leave
    ## a ceiling of handles reserved for rTorrent's internal needs!
    network.http.max_open.set = 50
    network.max_open_files.set = 600
    network.max_open_sockets.set = 300


    ## Memory resource usage (increase if you have a large number of items loaded,
    ## and/or the available resources to spend)
    pieces.memory.max.set = 1800M
    network.xmlrpc.size_limit.set = 4M


    ## Basic operational settings (no need to change these)
    session.path.set = (cat, (cfg.session))
    directory.default.set = (cat, (cfg.download))
    log.execute = (cat, (cfg.logs), "execute.log")
    #log.xmlrpc = (cat, (cfg.logs), "xmlrpc.log")
    execute.nothrow = sh, -c, (cat, "echo >",\
        (session.path), "rtorrent.pid", " ",(system.pid))


    ## Other operational settings (check & adapt)
    encoding.add = utf8
    system.umask.set = 0027
    system.cwd.set = (directory.default)
    network.http.dns_cache_timeout.set = 25
    schedule2 = monitor_diskspace, 15, 60, ((close_low_diskspace, 1000M))
    #pieces.hash.on_completion.set = no
    #view.sort_current = seeding, greater=d.ratio=
    #keys.layout.set = qwerty
    #network.http.capath.set = "/etc/ssl/certs"
    #network.http.ssl_verify_peer.set = 0
    #network.http.ssl_verify_host.set = 0


    ## Some additional values and commands
    method.insert = system.startup_time, value|const, (system.time)
    method.insert = d.data_path, simple,\
        "if=(d.is_multi_file),\
            (cat, (d.directory), /),\
            (cat, (d.directory), /, (d.name))"
    method.insert = d.session_file, simple, "cat=(session.path), (d.hash), .torrent"


    ## Watch directories (add more as you like, but use unique schedule names)
    ## Add torrent
    schedule2 = watch_load, 11, 10, ((load.verbose, (cat, (cfg.watch), "load/*.torrent")))
    ## Add & download straight away
    schedule2 = watch_start, 10, 10, ((load.start_verbose, (cat, (cfg.watch), "start/*.torrent")))


    ## Run the rTorrent process as a daemon in the background
    ## (and control via XMLRPC sockets)
    #system.daemon.set = true
    #network.scgi.open_local = (cat,(session.path),rpc.socket)
    #execute.nothrow = chmod,770,(cat,(session.path),rpc.socket)


    ## Logging:
    ##   Levels = critical error warn notice info debug
    ##   Groups = connection_* dht_* peer_* rpc_* storage_* thread_* tracker_* torrent_*
    print = (cat, "Logging to ", (cfg.logfile))
    log.open_file = "log", (cfg.logfile)
    log.add_output = "info", "log"
    #log.add_output = "tracker_debug", "log"

    ### begin: Handle magnet links specail way ###
    # helper method: checks existence of a directory, file, symlink
    method.insert = check_object.value, simple|private, "execute.capture=bash,-c,\"$cat=\\\"test -\\\",$argument.2=,\\\" \\\\\\\"\\\",$argument.0=,$argument.1=,\\\"\\\\\\\" && echo -n 1 || echo -n\\\"\""

    # Defining directory constants
    method.insert = cfg.incomplete, string|const|private, (cat,(cfg.basedir),"incomplete/")
    method.insert = cfg.meta_downl, string|const|private, (cat,(cfg.basedir),".downloading/")

    directory.default.set = (cat,(cfg.incomplete))
    session.path.set = (cat,(cfg.session))

    # Start any magnet torrent from the "load" watch directory (that only loads downloads into rtorrent)
    method.set_key = event.download.inserted_new, auto_start_meta_in_load_dir, "branch=\"and={d.is_meta=,not=$d.state=}\",d.start="

    # helper method: compose the full path of the wrong meta file in "incomplete" dir
    method.insert = d.get_wrong_magnet_meta_file_path,   simple|private, "cat=$cfg.incomplete=,$d.hash=,.meta"
    # helper method: compose the full path of the right torrent file in ".session" dir
    method.insert = d.get_session_magnet_meta_file_path, simple|private, "cat=$cfg.session=,$d.hash=,.torrent"
    # helper method: compose the new full path of the right torrent file in watch dir
    method.insert = d.get_new_magnet_meta_file_path,     simple|private, "cat=$cfg.meta_downl=,$d.name=,-,$d.hash=,.torrent"
    # helper method: delete wrong meta file from "incomplete dir"
    method.insert = d.delete_wrong_magnet_meta_file,     simple|private, "execute.nothrow={rm,-rf,--,$d.get_wrong_magnet_meta_file_path=}"
    # helper method: copy the right torrent file from ".session" dir into watch dir
    method.insert = d.copy_session_magnet_meta_file,     simple|private, "execute.nothrow={cp,--,$d.get_session_magnet_meta_file_path=,$d.get_new_magnet_meta_file_path=}"
    # helper method: copies right one into its proper place, sets d.tied_to_file property to it, deletes the wrong one, saves session
    method.insert = d.fix_magnet_tied_file, simple|private, "d.copy_session_magnet_meta_file=; d.tied_to_file.set=$d.get_new_magnet_meta_file_path=; d.delete_wrong_magnet_meta_file=; d.save_full_session="

    # Fix tied torrent file of an initially magnet link when its download has been just started: delete the wrong one from "incomplete" dir and copy the right one from ".session" dir if they exist
    method.set_key = event.download.inserted_new, fix_magnet_tied_file, "branch=\"and={\\\"check_object.value=$cat=$d.get_session_magnet_meta_file_path=,,f\\\",\\\"check_object.value=$cat=$d.get_wrong_magnet_meta_file_path=,,f\\\"}\",d.fix_magnet_tied_file="
    ### end: Handle magnet links specail way ###

    ### END of rtorrent.rc ###
  '';
in {
  imports = [
    ./flood-module
  ];

  options.kirk.servarr.rtorrent = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "enable rtorrent";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/servarr/rtorrent";
      description = lib.mdDoc "The state directory for rtorrent";
    };

    useVpn = mkOption {
      type = types.bool;
      default = config.kirk.servarr.vpn.enable;
      description = lib.mdDoc "Run rtorrent through VPN";
    };

    port = mkOption {
      type = types.port;
      default = 50000;
      description = "Rtorrent peer traffic port.";
    };

    dhtPort = mkOption {
      type = types.port;
      default = 6881;
      description = "Rtorrent dht port.";
    };

    usePublicTrackers = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Easier use of public trackers, if this is not enabled, will pick
        conservative settings for private trackers. Setting this to true
        should also be fine for private trackers.
      '';
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
        default = config.kirk.servarr.vpn.enable;
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
        default = "${config.kirk.servarr.stateDir}/flood";
        description = lib.mdDoc ''
          The directory for flood to keep its state in.
        '';
      };
    };

    ulimits = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
        Enable rtorrent ulimits. I had a bug that caused rtorrent to fail
        and log `std::bad_alloc`. Setting ulimits for this service fixed
        the issue. See link below for more info:

        https://stackoverflow.com/questions/75536471/rtorrent-docker-container-failing-to-start-saying-stdbad-alloc
      '';
      };

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

  config = mkIf cfg.enable {
    services.rtorrent = {
      enable = cfg.enable;
      configText = mkForce (defaultConfig ++ cfg.config);
      dataDir = "${cfg.stateDir}/servarr/rtorrent";
      downloadDir = "${cfg.mediaDir}/torrents";
      openFirewall = true;
      port = cfg.port;
    };

    services.flood = {
      enable = cfg.flood.enable;
      port = cfg.flood.port;
      openFirewall = true;
      auth.rtorrent.socket = config.services.rtorrent.rpcSocket;
    };

    kirk.vpnnamespace = {
      portMappings = [(
        mkIf cfg.flood.useVpn {
          From = cfg.flood.port;
          To = cfg.flood.port;
        }
      )];
      openUdpPorts = [ cfg.port ];
      openTcpPorts = [ cfg.port ];
    };

    # Create docker compose service for the servarr containers
    systemd = {
      services = { 
        rtorrent = mkIf cfg.useVpn {
          bindsTo = [ "netns@wg.service" ];
          requires = [ "network-online.target" ];
          after = [ "wg.service" ];
          serviceConfig = {
            NetworkNamespacePath = "/var/run/netns/wg";
            BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
          };
        };

        flood = mkIf cfg.flood.useVpn {
          bindsTo = [ "netns@wg.service" ];
          requires = [ "network-online.target" ];
          after = [ "wg.service" ];
          serviceConfig = {
            NetworkNamespacePath = "/var/run/netns/wg";
            BindReadOnlyPaths="/etc/netns/wg/resolv.conf:/etc/resolv.conf:norbind";
          };
        };
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
