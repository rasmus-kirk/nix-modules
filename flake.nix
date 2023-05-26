{
  description = "Kirk nix modules";

  inputs = {};

  outputs = {
    self,
    }: {
    nixosModules.kirk = import ./nixos;
    nixosModules.default = self.nixosModules.kirk;

    homeManagerModules.kirk = import ./home-manager;
    homeManagerModules.default = self.homeManagerModules.kirk;

    # TODO: Find a way to generate documentation from modules using the same
    #       tools as nixos. See ./mkDocs.nix

    #packages.x86_64-linux.mkdocs = {}; 
    #defaultPackage.x86_64-linux = self.packages.x86_64-linux.report;
  };
}