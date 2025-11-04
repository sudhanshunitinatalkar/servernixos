{
  description = "cosmos";

  inputs = 
  {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = 
    {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }: 
  {
    nixosConfigurations.servernixos = nixpkgs.lib.nixosSystem
    {
      modules = 
      [
        home-manager.nixosModules.home-manager
        ./hosts/servernixos.nix
        ./hosts/hardware-servernixos.nix
      ];
    };
  };
}
