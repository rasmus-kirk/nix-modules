{
  lib,
  pkgs,
  nixosOptionsDoc,
  inputs,
  ...
}: let
  # Make sure the used package is scrubbed to avoid actually
  # instantiating derivations.
  # evaluate our options
  evalHome = lib.evalModules {
    # TODO: understand why pkgs needs to be passed here
    specialArgs = {inherit pkgs;};
    modules = [
      {
        # disabled checking that all option definitions have matching declarations
        config._module.check = false;
      }
      inputs.home-manager.nixosModules.default
      ./home-manager
      #./home-manager/foot
      #./home-manager/fzf
      #./home-manager/git
      #./home-manager/gruvboxTheme
      #./home-manager/helix
      #./home-manager/homeManagerScripts
      #./home-manager/jiten
      #./home-manager/joshuto
      #./home-manager/kakoune
      #./home-manager/ssh
      #./home-manager/terminalTools
      #./home-manager/userDirs
      #./home-manager/zathura
      #./home-manager/zsh
    ];
  };
  # generate our docs
  optionsDocHome = nixosOptionsDoc {
    inherit (evalHome) options;
  };

  # Same for nixos
  evalNixos = lib.evalModules {
    specialArgs = {inherit pkgs;};
    modules = [
      {
        config._module.check = false;
      }
      inputs.home-manager.nixosModules.default
      ./nixos/servarr
      ./nixos/nixosScripts
    ];
  };
  optionsDocNixos = nixosOptionsDoc {
    inherit (evalNixos) options;
  };
in pkgs.stdenv.mkDerivation {
    name = "nixdocs2html";
    src = ./.;
    buildInputs = with pkgs; [ pandoc ];
    phases = ["unpackPhase" "buildPhase"];
    buildPhase = ''
      tmpdir=$(mktemp -d)
      mkdir -p $out
      cp docs/styling/style.css $out

      buildpandoc () {
        file_path="$1"
        filename=$(basename -- "$file_path")
        filename_no_ext="''${filename%.*}"
        echo "$file_path"
        echo "$1"

        # Remove "Declared by" lines
        sed '/\*Declared by:\*/{N;d;}' "$file_path" > "$tmpdir"/"$filename_no_ext"1.md

        echo 2

        # Code blocks to nix code blocks
        # shellcheck disable=SC2016
        awk '
        /^```$/ {
            if (!block) {
                print "```nix";  # Start of a code block
                block = 1;
            } else {
                print "```";  # End of a code block
                block = 0;
            }
            next;
        }
        { print }  # Print all lines, including those inside code blocks
        ' block=0 "$tmpdir"/"$filename_no_ext"1.md > "$tmpdir"/"$filename_no_ext"2.md
        # inline code "blocks" to nix code blocks
        # shellcheck disable=SC2016
        sed '/^`[^`]*`$/s/`\(.*\)`/```nix\n\1\n```/g' "$tmpdir"/"$filename_no_ext"2.md > "$tmpdir"/"$filename_no_ext"3.md
        echo 3
        # Remove bottom util-nixarr options
        sed '/util-nixarr/,$d' "$tmpdir"/"$filename_no_ext"3.md > "$tmpdir"/done.md
        echo 4

        pandoc \
          --standalone \
          --highlight-style docs/styling/gruvbox.theme \
          --metadata title="Kirk Modules - Option Documentation" \
          --metadata date="$(date -u '+%Y-%m-%d - %H:%M:%S %Z')" \
          --css=style.css \
          -V lang=en \
          -V --mathjax \
          -f markdown+smart \
          -o $out/"$filename_no_ext".html \
          "$tmpdir"/done.md
      }

      # Generate nixos md docs
      cat ${optionsDocNixos.optionsCommonMark} | tail -n +58 >> "$tmpdir"/nixos.md
      # Generate home-manager md docs
      cat ${optionsDocHome.optionsCommonMark} | tail -n +58 >> "$tmpdir"/home.md

      buildpandoc "$tmpdir"/nixos.md
      buildpandoc "$tmpdir"/home.md

        pandoc \
          --standalone \
          --highlight-style docs/styling/gruvbox.theme \
          --metadata title="Kirk Modules - Option Documentation" \
          --metadata date="$(date -u '+%Y-%m-%d - %H:%M:%S %Z')" \
          --css=style.css \
          -V lang=en \
          -V --mathjax \
          -f markdown+smart \
          -o $out/index.html \
          docs/index.md
    '';
  }



