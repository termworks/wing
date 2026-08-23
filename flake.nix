{
  description = "robolibs crate development shell";

  inputs = {
    # Pinned to a rev that still accepts the `kernel` arg in
    # nvidia-x11/generic.nix. Newer nixpkgs (post 2026-04) dropped
    # that arg, which breaks nixGL until upstream catches up. Bump
    # together with nixgl when its corresponding fix lands.
    nixpkgs.url = "github:NixOS/nixpkgs?rev=4c1018dae018162ec878d42fec712642d214fdfa";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs =
    { nixpkgs, flake-utils, nixgl, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [
          (final: prev: {
            xorg = prev.xorg // {
              libX11 = final.libx11;
              libxcb = final.libxcb;
              libxshmfence = final.libxshmfence;
            };
          })
        ];

        pkgs = import nixpkgs {
          inherit system overlays;
          config = {
            allowUnfree = true;
            nvidia.acceptLicense = true;
          };
        };

        nvidiaVersion = builtins.getEnv "NVIDIA_VERSION";
        hasNvidia = nvidiaVersion != "";

        nixglPkgs = import "${nixgl}/default.nix" ({
          inherit pkgs;
        } // pkgs.lib.optionalAttrs hasNvidia {
          inherit nvidiaVersion;
          nvidiaHash = null;
        });

        nixGLTarget =
          if hasNvidia
          then "${nixglPkgs.nixGLNvidia}/bin/nixGLNvidia-${nvidiaVersion}"
          else "${nixglPkgs.nixGLIntel}/bin/nixGLIntel";
        nixVulkanTarget =
          if hasNvidia
          then "${nixglPkgs.nixVulkanNvidia}/bin/nixVulkanNvidia-${nvidiaVersion}"
          else "${nixglPkgs.nixVulkanIntel}/bin/nixVulkanIntel";

        nixGLAlias = pkgs.runCommand "nixGL" { } ''
          mkdir -p $out/bin
          ln -s ${nixGLTarget} $out/bin/nixGL
        '';
        nixVulkanAlias = pkgs.runCommand "nixVulkan" { } ''
          mkdir -p $out/bin
          ln -s ${nixVulkanTarget} $out/bin/nixVulkan
        '';

        # Lua comes from nixpkgs rather than being vendored, so none of its C source lives in this
        # repository and the version is pinned by flake.lock like everything else. Both builds are
        # here because a static binary needs a libc-matched archive: liblua.a from the glibc build
        # cannot go into a musl link.
        #
        # Deliberately env vars rather than `packages` entries. A package puts its headers on the
        # default search path, and musl's there makes an ordinary `nim c` compile against musl and
        # link against glibc -- which builds without a word and then segfaults. Only the build that
        # wants a path is given it: `config.nims` reads WING_LUA and passes the flags itself.
        buildEnv = {
          LUA_DEV = pkgs.lua5_4;
          LUA_MUSL = pkgs.pkgsMusl.lua5_4;
          MUSL_DEV = pkgs.musl.dev;
        };

        # Everything needed to compile and check the source, and nothing else. CI enters this
        # rather than the full shell so it does not pull mdbook, nixGL and git-cliff -- none of
        # which it uses -- across the network on every job.
        buildTools = [
          pkgs.nim
          pkgs.nimble
          pkgs.gcc
          # readelf for the staticness check, and file for the report. readelf is the one that
          # decides it: ldd prints "statically linked" for a binary that still carries an INTERP
          # and will not start.
          pkgs.binutils
          pkgs.file
          pkgs.pkg-config
        ];

        guiLibs = with pkgs; [
          alsa-lib
          udev
          vulkan-loader
          libxkbcommon
          wayland
          libx11
          libxcursor
          libxi
          libxrandr
        ];
      in
      {
        # The Nim version is pinned in exactly one place: this flake, through flake.lock. CI enters
        # `.#ci` rather than installing a Nim of its own, so there is no second pin that can drift
        # out from under the formatter and the release build.
        devShells.ci = pkgs.mkShell (buildEnv // { packages = buildTools; });

        devShells.default = pkgs.mkShell (buildEnv // {
          packages = [
            pkgs.nim
            pkgs.nimble
            pkgs.nimlsp
            pkgs.nimlangserver
            pkgs.git-cliff
            pkgs.clang
            pkgs.mold
            pkgs.pkg-config

            nixGLAlias
            nixVulkanAlias
            nixglPkgs.nixGLIntel
            nixglPkgs.nixVulkanIntel
          ] ++ pkgs.lib.optionals hasNvidia [
            nixglPkgs.nixGLNvidia
            nixglPkgs.nixVulkanNvidia
          ] ++ guiLibs;

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath guiLibs;
          WGPU_VALIDATION = "0";
          WGPU_DEBUG = "0";
        });
      }
    );
}
