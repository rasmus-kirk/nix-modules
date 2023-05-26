{
  description = "Kirk nix modules";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #home-manager = {
    #  url = "github:nix-community/home-manager";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
  };

  outputs = {
    self,
    #nixpkgs,
    #home-manager,
  }: {
    nixosModules.kirk = import ./nixos;
    nixosModules.default = self.nixosModules.kirk;

    homeManagerModules.kirk = import ./home-manager;
    homeManagerModules.default = self.homeManagerModules.kirk;

    # Work-around for https://github.com/nix-community/home-manager/issues/3075
    #legacyPackages = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-darwin"] (system: {
    #  homeConfigurations.integration-darwin = home-manager.lib.homeManagerConfiguration {
    #    pkgs = nixpkgs.legacyPackages.${system};
    #    modules = [./test/integration_hm_darwin.nix];
    #  };
    #});
  };
}