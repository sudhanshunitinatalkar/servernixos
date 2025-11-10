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

    postgresql = 
    {
      enable = true;
      # Ensure standard authentication methods are set:
      # - 'local all all peer': Allows users to connect via socket if their OS username matches the DB username.
      # - 'host all all 127.0.0.1/32 scram-sha-256': Requires password for TCP connections (used by ThingsBoard).
      authentication = pkgs.lib.mkOverride 10 ''
        #type database  DBuser  auth-method
        local all       all     peer
        host  all       all     127.0.0.1/32   scram-sha-256
        host  all       all     ::1/128        scram-sha-256
      '';
    };

    cloudflared = {
      enable = true;
      tunnels = {
        "70d40540-2e65-4354-ba69-6d7ac6484a0e" = {
          credentialsFile = "/home/pbrserver/.cloudflared/70d40540-2e65-4354-ba69-6d7ac6484a0e.json";
          ingress = {
            "iot.eltros.in" = "http://localhost:8080";
            "mqtt.eltros.in" = "tcp://localhost:1883";
            "mqtts.eltros.in" = "tcp://localhost:8883";
          };
          default = "http_status:404";
        };
      };
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

