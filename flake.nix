{
  description = "Nix Buildproxy (multi-system flake using flake-utils)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      # Define a per-system function that returns the actual system outputs
      perSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (final: prev: {
                mitmproxy = prev.mitmproxy.overrideAttrs (oldAttrs: {
                  propagatedBuildInputs = oldAttrs.propagatedBuildInputs ++ [ prev.python3Packages.httpx ];
                });
              })
            ];
          };

          mkContent =
            proxy-content-file:
            pkgs.callPackage ./nix-buildproxy/build-content.nix {
              proxy_content = import proxy-content-file;
            };

          mkBuildproxy =
            proxy-content-file:
            pkgs.callPackage ./nix-buildproxy/buildproxy.nix {
              inherit self;
              content = mkContent proxy-content-file;
            };

          mkBuildproxyShell =
            proxy-content-file:
            pkgs.callPackage ./nix-buildproxy/buildproxy-shell.nix {
              inherit self;
              content = mkContent proxy-content-file;
            };
        in
        {
          lib = { inherit mkBuildproxy mkBuildproxyShell; };

          packages = {
            example = pkgs.callPackage ./example/example.nix {
              buildproxy = mkBuildproxy ./example/proxy_content.nix;
            };
            buildproxy-capture = pkgs.callPackage ./nix-buildproxy/buildproxy-capture.nix {
              inherit self;
            };
            default = self.packages.${system}.buildproxy-capture;
          };

          devShells = {
            example = pkgs.callPackage ./example/devshell.nix {
              buildproxy-capture = self.packages.${system}.buildproxy-capture;
            };

            nix-buildproxy = pkgs.callPackage ./nix-buildproxy/devshell.nix {
              inherit (self.packages.${system}) buildproxy-capture;
              buildproxy-shell = mkBuildproxyShell ./proxy_content.nix;
            };

            default = self.devShells.${system}.nix-buildproxy;
          };
        };
    in
    # Top-level outputs: expose overlays and per-system outputs
    flake-utils.lib.eachDefaultSystem (system: perSystem system)
    // {
      overlays.default = final: prev: {
        buildproxy-capture =
          (flake-utils.lib.eachDefaultSystem (system: perSystem system))
          .${prev.system}.packages.buildproxy-capture or null;
        lib = prev.lib // {
          mkBuildproxy = (perSystem prev.system).lib.mkBuildproxy;
          mkBuildproxyShell = (perSystem prev.system).lib.mkBuildproxyShell;
        };
      };
    };
}
