{ config, pkgs, lib, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "vals";
  home.homeDirectory = "/home/vals";

  # allow unfree software
  nixpkgs.config.allowUnfree = true;

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
  # common
    htop
    wget
    curl
    tmux
    nnn
    fastfetch
    tree
    ncdu
    direnv
    # https://github.com/ibraheemdev/modern-unix
    bat # modern cat
    eza # ls
    duf # du
    fd # find
    mcfly # sh history navigator
    tldr # man
    hyperfine # command-line benchmarking tool
    fzf # A command-line fuzzy finder
    plocate # fast locate

    # archives
    zip
    xz
    unzip
    p7zip

    # networking tools
    mtr # A network diagnostic tool
    iperf3
    dnsutils  # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc  # it is a calculator for the IPv4/v6 addresses

    # misc
    cowsay
    file
    which
    gnused
    gnutar
    gawk
    zstd
    gnupg

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    # productivity
    hugo # static site generator
    glow # markdown previewer in terminal

    btop  # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
    keyd # system-wide key remapping CLI; daemon is deployed separately

    # dev
    git
    gh # github cli client
    glab # gitlab cli client
    difftastic
    jq # json cli tool
    httpie # curl
    curlie # curl
    ripgrep # recursively searches directories for a regex pattern
    ast-grep # structural code search and rewrite
    yq-go # yaml processer https://github.com/mikefarah/yq
    shellcheck # shell static analysis
    shfmt # shell formatter
    watchexec # rerun commands when files change
    gnumake
    emacs
    nerd-fonts.symbols-only # icon glyphs used by doom-modeline/nerd-icons
    neovim
    vimPlugins.LazyVim
    mise # manage dev environment
    lazygit
    lazydocker
    gum # iteractive shell menu creation

    # privacy and secret hygiene
    age
    sops
    restic
    gitleaks
    mat2

    # language servers
    clang-tools
    zls
    yaml-language-server
    nixd
    rust-analyzer

    # java / spring boot
    jdk25
    maven
    gradle
    jdt-language-server
    google-java-format
    spring-boot-cli

    # documentation
    plantuml
    graphviz
    texlive.combined.scheme-full
    obsidian

    # utils
    localsend   # AirDrop alternative
    vlc
    flameshot # screenshot tool
    xournalpp # handwriting tool with pdf annotation support
    pinta # quick image editing
    foot
    zellij

    # desktop runtime dependencies
    niri
    waybar
    swaybg
    fuzzel
    wl-clipboard
    cliphist
    swaylock
    playerctl
    brightnessctl
    pamixer
    blueman
    impala
    wiremix
    xwayland-satellite
  ];

  fonts.fontconfig.enable = true;

  programs = {
    firefox = {
      enable = true;
      configPath = ".mozilla/firefox";
      policies = {
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        HttpsOnlyMode = "enabled";
        EnableTrackingProtection = {
          Value = true;
          Cryptomining = true;
          EmailTracking = true;
          Fingerprinting = true;
          SuspectedFingerprinting = true;
        };
        ExtensionSettings = {
          "uBlock0@raymondhill.net" = {
            installation_mode = "normal_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          };
          "keepassxc-browser@keepassxc.org" = {
            installation_mode = "normal_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi";
          };
        };
      };
    };

    # Keep the application settings mutable; Home Manager only owns the
    # package and browser native-messaging manifest.
    keepassxc.enable = true;

    noctalia = {
      enable = true;
      systemd.enable = false;

      settings = {
        shell = {
          font_family = "CaskaydiaMono Nerd Font";
          telemetry_enabled = false;
          polkit_agent = true;
          clipboard_enabled = true;
          clipboard_history_max_entries = 20;
          launch_apps_as_systemd_services = false;
        };

        storage.key_source = "secret-service";

        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Zenburn";
        };

        wallpaper = {
          enabled = true;
          fill_mode = "crop";
          default.path = "${config.home.homeDirectory}/.local/share/backgrounds/background.jpg";
        };

        notification = {
          enable_daemon = true;
          show_app_name = true;
          show_actions = true;
          background_opacity = 0.97;
        };

        lockscreen.enabled = true;
        brightness.enable_ddcutil = false;

        idle.behavior.lock = {
          enabled = true;
          timeout = 600;
          action = "lock";
        };
        idle.behavior.screen-off = {
          enabled = true;
          timeout = 660;
          action = "screen_off";
        };

        bar.main = {
          position = "top";
          thickness = 26;
          background_opacity = 0.92;
          radius = 0;
          margin_ends = 0;
          margin_edge = 0;
          padding = 8;
          widget_spacing = 6;
          shadow = false;
          capsule = false;
          reserve_space = true;
          start = [ "workspaces" ];
          center = [ "clock" ];
          end = [
            "tray"
            "keyboard_layout"
            "network"
            "bluetooth"
            "volume"
            "battery"
            "control-center"
          ];
        };

        widget.workspaces = {
          style = "minimal";
          show_labels = true;
          label_source = "name";
          max_label_chars = 10;
          labels_only_when_occupied = false;
          hide_when_empty = false;
        };
        widget.clock = {
          format = "{:%A %H:%M}";
          tooltip_format = "{:%d %B W%V %Y}";
        };
        widget.network.show_label = false;
        widget.bluetooth.show_label = false;
        widget.volume.show_label = false;
        widget.battery.show_label = false;

        dock.enabled = false;
        desktop_widgets.enabled = false;
        backdrop.enabled = false;
      };

      customPalettes = {
        Zenburn = {
          dark = {
            mPrimary = "#7F9F7F";
            mOnPrimary = "#1E2320";
            mSecondary = "#8CD0D3";
            mOnSecondary = "#1E2320";
            mTertiary = "#DFAF8F";
            mOnTertiary = "#1E2320";
            mError = "#CC9393";
            mOnError = "#1E2320";
            mSurface = "#2B2B2B";
            mOnSurface = "#DCDCCC";
            mSurfaceVariant = "#3F3F3F";
            mOnSurfaceVariant = "#C3BF9F";
            mOutline = "#5F5F5F";
            mShadow = "#1E2320";
            mHover = "#4F4F4F";
            mOnHover = "#DCDCCC";
            terminal = {
              background = "#3A3A3A";
              foreground = "#DCDCCC";
              cursor = "#DCDCCC";
              cursorText = "#3A3A3A";
              selectionBg = "#DCDCCC";
              selectionFg = "#3A3A3A";
              normal = {
                black = "#1E2320";
                red = "#D78787";
                green = "#60B48A";
                yellow = "#DFAF8F";
                blue = "#506070";
                magenta = "#DC8CC3";
                cyan = "#8CD0D3";
                white = "#DCDCCC";
              };
              bright = {
                black = "#709080";
                red = "#DCA3A3";
                green = "#C3BF9F";
                yellow = "#F0DFAF";
                blue = "#94BFF3";
                magenta = "#EC93D3";
                cyan = "#93E0E3";
                white = "#FFFFFF";
              };
            };
          };
          light = {
            mPrimary = "#5F7F5F";
            mOnPrimary = "#FFFFFF";
            mSecondary = "#4F8F8F";
            mOnSecondary = "#FFFFFF";
            mTertiary = "#9F6F4F";
            mOnTertiary = "#FFFFFF";
            mError = "#A85F5F";
            mOnError = "#FFFFFF";
            mSurface = "#DCDCCC";
            mOnSurface = "#1E2320";
            mSurfaceVariant = "#C3BF9F";
            mOnSurfaceVariant = "#2B2B2B";
            mOutline = "#709080";
            mShadow = "#3A3A3A";
            mHover = "#B8B8A0";
            mOnHover = "#1E2320";
            terminal = {
              background = "#DCDCCC";
              foreground = "#1E2320";
              cursor = "#1E2320";
              cursorText = "#DCDCCC";
              selectionBg = "#1E2320";
              selectionFg = "#DCDCCC";
              normal = {
                black = "#DCDCCC";
                red = "#A85F5F";
                green = "#5F7F5F";
                yellow = "#9F6F4F";
                blue = "#506070";
                magenta = "#9F5F8F";
                cyan = "#4F8F8F";
                white = "#1E2320";
              };
              bright = {
                black = "#709080";
                red = "#A85F5F";
                green = "#5F7F5F";
                yellow = "#9F6F4F";
                blue = "#506070";
                magenta = "#9F5F8F";
                cyan = "#4F8F8F";
                white = "#000000";
              };
            };
          };
        };
      };
    };

    bat.enable = true;
    zsh = {
      enable = true;
      shellAliases = {
        ".." = "cd ..";
        kport = "function _kport() { lsof -i tcp:\"$@\" | awk 'NR==2{print $2}' | xargs kill; };_kport";
      };
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
      enableZshIntegration = true;
    };

    git = {
      enable = true;
      settings = {
        alias = {
          st = "status";
        };
      };
      includes = [
        { path = "~/Dropbox/config/.gitconfig"; }
      ];
    };

    starship = {
      enable = true;
      # custom settings
      settings = {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = true;
      };
    };

    # unfree software
    vscode = {
      enable = true;
    };
  };

  home.sessionVariables = {
    BROWSER = "firefox";
    JAVA_HOME = "${pkgs.jdk25}";
    JAVA_17_HOME = "${pkgs.jdk17.home}";
    JAVA_25_HOME = "${pkgs.jdk25.home}";
    TERMINAL = "foot";
  };

  xdg.configFile."xdg-terminals.list".text = ''
    foot.desktop
  '';

  # Keep MIME associations mutable and change only the browser defaults.
  home.activation.setFirefoxDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.xdg-utils}/bin/xdg-mime default firefox.desktop text/html
    run ${pkgs.xdg-utils}/bin/xdg-mime default firefox.desktop x-scheme-handler/http
    run ${pkgs.xdg-utils}/bin/xdg-mime default firefox.desktop x-scheme-handler/https
  '';

  # copy dot files
  home.file.".config/foot/foot.ini".source = ./foot/foot.ini;
  home.file.".tmux.conf".source                       = ./.tmux.conf;
  home.file.".emacs.d/tree-sitter/libtree-sitter-java.so".source =
    "${pkgs.tree-sitter-grammars.tree-sitter-java}/parser";
  home.file.".local/share/jdks/17".source = "${pkgs.jdk17.home}";
  home.file.".local/share/jdks/25".source = "${pkgs.jdk25.home}";
  home.file.".agents/skills/manage-makefile" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Github/config/skills/manage-makefile";
  };
  home.file.".claude/skills/manage-makefile" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Github/config/skills/manage-makefile";
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
