{
  description = "cosmos";

  inputs = 
  {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = 
    {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }: 
  {
    nixosConfigurations.pbrserver = nixpkgs.lib.nixosSystem
    {
      modules = 
      [
        home-manager.nixosModules.home-manager
        ./hosts/configuration.nix
        ./hosts/hardware-configuration.nix
        ./modules/thingsboard.nix     
      ];
    };
  };
}