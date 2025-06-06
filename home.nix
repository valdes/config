{ config, pkgs, ... }:

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
    ripgrep # grep
    mcfly # sh history navigator
    tldr # man
    hyperfine # command-line benchmarking tool
    fzf # A command-line fuzzy finder
    zoxide # z fast cd
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

    # dev
    git
    gh # github cli client
    difftastic
    jq # json cli tool
    httpie # curl
    curlie # curl
    ripgrep # recursively searches directories for a regex pattern
    yq-go # yaml processer https://github.com/mikefarah/yq
    gnumake
    emacs
    neovim
    vimPlugins.LazyVim
    mise # manage dev environment
    lazygit
    lazydocker
    gum # iteractive shell menu creation
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
    alacritty
    zellij
  ];

  programs = {
    bat.enable = true;
    zsh = {
    	enable = true;
	    oh-my-zsh = {
		    enable = true;
   		    plugins = [ "git" "z" "rails" ];
  		    theme = "robbyrussell";
  		};
      shellAliases = {
        ".." = "cd ..";
         kport ="function _kport() { lsof -i tcp:\"$@\" | awk 'NR==2{print $2}' | xargs kill; };_kport";
      };
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
      aliases = {
        st = "status";
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

  # copy dot files
  home.file.".config/alacritty/alacritty.toml".source = ~/Github/config/zenburn.toml;
  home.file.".tmux.conf".source                       =  ~/Github/config/.tmux.conf;

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
