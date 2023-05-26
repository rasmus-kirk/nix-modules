{ lib, pkgs, nixosOptionsDoc, ...}:
    let
    # evaluate our options
    eval = lib.evalModules {
        check = false;
        modules = [
            ./home-manager/fonts
            ./home-manager/foot
            ./home-manager/fzf
            ./home-manager/git
            ./home-manager/gruvboxTheme
            ./home-manager/helix
            ./home-manager/homeManagerScripts
            ./home-manager/jiten
            ./home-manager/joshuto
            ./home-manager/kakoune
            ./home-manager/ssh
            ./home-manager/terminalTools
            ./home-manager/userDirs
            ./home-manager/zathura
            ./home-manager/zsh
        ];
    };
    # generate our docs
    optionsDoc = nixosOptionsDoc {
        inherit (eval) options;
    };
in
    # create a derivation for capturing the markdown output
    pkgs.runCommand "options-doc.md" {} ''
        cat ${optionsDoc.optionsCommonMark} >> $out
    ''