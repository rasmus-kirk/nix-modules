{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.zathura;
in {
  options.kirk.zathura = {
    enable = mkEnableOption "foot terminal emulator";

    colorscheme = mkOption {
      type = types.attrs;
      default = config.kirk.gruvbox.colorscheme;

      description = ''
        A colorscheme attribute set.
      '';
    };

    darkmode = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Enable darkmode on recolor.
      '';
    };

    enableKeyBindings = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Whether or not to enable my keybindings.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.zathura = {
      enable = true;

      options = mkMerge [
        {
          selection-clipboard = "clipboard";
          recolor-reverse-video = "true";
          recolor-keephue = "true";
          highlight-transparency = 0.4;
        }
        (mkIf (cfg.colorscheme != {} && !cfg.darkmode) {
          default-bg = "#${cfg.colorscheme.bg}";
          default-fg = "#${cfg.colorscheme.fg}";
          statusbar-fg = "#${cfg.colorscheme.fg}";
          statusbar-bg = "#${cfg.colorscheme.black}";
          inputbar-bg = "#${cfg.colorscheme.bg}";
          inputbar-fg = "#${cfg.colorscheme.white}";
          notification-bg = "#${cfg.colorscheme.fg}";
          notification-fg = "#${cfg.colorscheme.bg}";
          notification-error-bg = "#${cfg.colorscheme.red}";
          notification-error-fg = "#${cfg.colorscheme.fg}";
          notification-warning-bg = "#${cfg.colorscheme.yellow}";
          notification-warning-fg = "#${cfg.colorscheme.fg}";
          highlight-color = "#${cfg.colorscheme.bright.yellow}";# " #0A"
          highlight-active-color = "#${cfg.colorscheme.bright.green}";# " #0D"
          recolor-lightcolor = "#${cfg.colorscheme.bright.fg}";
          recolor-darkcolor = "#${cfg.colorscheme.bg}";
        })
        (mkIf (cfg.colorscheme != {} && cfg.darkmode) {
          default-bg = "#${cfg.colorscheme.bg}";
          default-fg = "#${cfg.colorscheme.fg}";
          statusbar-fg = "#${cfg.colorscheme.fg}";
          statusbar-bg = "#${cfg.colorscheme.black}";
          inputbar-bg = "#${cfg.colorscheme.bg}";
          inputbar-fg = "#${cfg.colorscheme.white}";
          notification-bg = "#${cfg.colorscheme.fg}";
          notification-fg = "#${cfg.colorscheme.bg}";
          notification-error-bg = "#${cfg.colorscheme.red}";
          notification-error-fg = "#${cfg.colorscheme.fg}";
          notification-warning-bg = "#${cfg.colorscheme.yellow}";
          notification-warning-fg = "#${cfg.colorscheme.fg}";
          highlight-color = "#${cfg.colorscheme.bright.yellow}";# " #0A"
          highlight-active-color = "#${cfg.colorscheme.bright.green}";# " #0D"
          recolor-lightcolor = "#${cfg.colorscheme.bg}";
          recolor-darkcolor = "#${cfg.colorscheme.fg}";
        })
      ];

      mappings = mkIf cfg.enableKeyBindings {
        f = "toggle_fullscreen";
        r = "reload";
        R = "rotate";
        H = "navigate previous";
        K = "zoom out";
        J = "zoom in";
        L = "navigate next";
        i = "recolor";
        "<A-n>" = "search backward";
        "<Right>" = "navigate next";
        "<Left>" = "navigate previous";
        "[fullscreen] f" = "toggle_fullscreen";
        "[fullscreen] r" = "reload";
        "[fullscreen] R" = "rotate";
        "[fullscreen] H" = "navigate -1";
        "[fullscreen] K" = "zoom out";
        "[fullscreen] J" = "zoom in";
        "[fullscreen] L" = "navigate 1";
        "[fullscreen] i" = "recolor";
        "[fullscreen] <Right>" = "navigate next";
        "[fullscreen] <Left>" = "navigate previous";
      };
    };
  };
}
