{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "vals";
  home.homeDirectory = "/home/vals";

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
  # common
    htop
    wget
    curl
    tmux
    nnn
    tree
    ncdu
    direnv
    # https://github.com/ibraheemdev/modern-unix
    bat # modern cat
    exa # ls
    duf # du
    fd # find
    ripgrep # grep
    mcfly # sh history navigator
    tldr # man

    # dev
    git
    difftastic
    jq # json cli tool
    httpie # curl
    curlie # curl
  ];

  programs = {
    bat.enable = true;

    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
    };

#     git = {
#       enable = true;
#       userName = "Luis Valdés Guerrero1";
#       userEmail = "lguerrero85@gmail.com";
#       editor = "emacs";
#       helper = "store";
#       aliases = {
#         st = "status";
#       };
#     };
  };


  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "22.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
