# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.servarr.jellyfin;
  servarr = config.kirk.servarr;
in {
  options.kirk.servarr.jellyfin = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc "enable jellyfin";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${servarr.stateDir}/servarr/jellyfin";
      description = lib.mdDoc "The state directory for jellyfin";
    };

    nginx = {
      enable = mkEnableOption "Enable nginx for jellyfin";

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
    };
  };

  config = mkIf cfg.enable {
    services.jellyfin = mkIf cfg.enable {
      enable = cfg.enable;
      openFirewall = true;
    };

    networking.firewall.allowedTCPPorts = [ 
      80 # http
      443 # https
    ];

    services.nginx = mkIf (cfg.nginx.enable && cfg.enable) {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${builtins.replaceStrings ["\n"] [""] cfg.nginx.domainName}" = {
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
      defaults.email = cfg.nginx.acmeMail;
    };
  };
}
