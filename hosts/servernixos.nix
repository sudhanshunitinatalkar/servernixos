{ config, lib, pkgs, ... }:

{

  system.stateVersion = "25.05";
  
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  home-manager = 
  {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.servernixos = {
      imports = [ ./users/servernixos.nix ];
    };
  };

  users.users.servernixos = 
  {
    isNormalUser = true;
    extraGroups = [ "wheel" "dialout" ];
  };

  boot = 
  {
    kernelPackages = pkgs.linuxPackages;
    loader = 
    {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    
  };

  hardware.bluetooth.enable = true;

  networking = 
  {
    hostName = "servernixos";
    networkmanager.enable = true;
    firewall.enable = false;
    # firewall.allowedTCPPorts = [ ];
    # firewall.allowedUDPPorts = [ ];
  };
  
  programs = 
  {
    firefox.enable = true;
  };

  services = 
  {
    libinput.enable = true;
    openssh.enable = true;

    cloudflared.enable = true;
    postgresql.enable = true;
    
  };

  environment.systemPackages = with pkgs; 
  [
    tree
    util-linux
    vim
    wget
    curl
    git
    gptfdisk
    htop
    pciutils
    home-manager
  ];

  time.timeZone = "Asia/Kolkata";

  i18n.defaultLocale = "en_US.UTF-8";
  console = 
  {
    font = "Lat2-Terminus16";
    keyMap = "us";
    #useXkbConfig = true;
  };

}

