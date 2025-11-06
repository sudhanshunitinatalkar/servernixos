{ config, lib, pkgs, ... }:

{

  system.stateVersion = "25.05";
  
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  home-manager = 
  {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.pbrserver = {
      imports = [ ../home/home.nix ];
    };
  };

  users.users.pbrserver = 
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
    hostName = "pbrserver";
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

    postgresql = 
    {
      enable = true;
      ensureUsers = 
      [{
        name = "thingsboard";
        passwordFile = "/etc/nixos/secrets/thingsboard.pass";
      }];
      ensureDatabases = 
      [{
        name = "thingsboard";
        owner = "thingsboard";
      }];
    };

    thingsboard = 
    {
      enable = true;
      dbPasswordFile = "/etc/nixos/secrets/thingsboard.pass";
    };    
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

