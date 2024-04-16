{
  pkgs,
  config,
  lib,
  self,
  ...
}: let
  nixGLWrap = pkg:
    pkgs.runCommand "${pkg.name}-nixgl-pkg-wrapper" {} ''
      # Create a new package that wraps the binaries with nixGL
      mkdir $out
      ln -s ${pkg}/* $out
      rm $out/bin
      mkdir $out/bin
      for bin in ${pkg}/bin/*
      do
       wrapped_bin=$out/bin/$(basename $bin)
       echo "#!/bin/sh" > $wrapped_bin
       echo "exec nixgl $bin \"\$@\"" >> $wrapped_bin
       chmod +x $wrapped_bin
      done

      # If .desktop files refer to the old derivation, replace the references
      if [ -d "${pkg}/share/applications" ] && grep "${pkg}" ${pkg}/share/applications/*.desktop > /dev/null
      then
          rm $out/share
          mkdir -p $out/share
          cd $out/share
          ln -s ${pkg}/share/* ./
          rm applications
          mkdir applications
          cd applications
          cp -a ${pkg}/share/applications/* ./
          for dsk in *.desktop
          do
              sed -i "s|${pkg}|$out|g" "$dsk"
          done
      fi
    '';
in {
  options.nixgl = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.targets.genericLinux.enable;
      description = ''
        Whether to enable nixGL wrapper for OpenGL support on non-NixOS systems.
        Enabled by default when targets.genericLinux.enabled is true.
      '';
    };
  };

  config = {
    nixpkgs.overlays = [
      (final: prev: {
        gpu-wrappers = let
          system = prev.system;
          nixglPkgs = "${self}#gpuWrappers.${system}";
          wrapIntel = type: lib.getExe self.inputs.nixgl.packages.${system}."nix${type}Intel";
          wrapNvidia = type: ''
            nix shell --quiet --impure ${nixglPkgs}.nix${type}Nvidia -c nix${type}Nvidia-$()
          '';
        in
          pkgs.runCommand "gpu-wrappers" {} ''
            bin=$out/bin
            mkdir -p $bin

            cat > $bin/nixgl-intel <<EOF
            #!/bin/sh
            exec ${wrapIntel "GL"} ${wrapIntel "Vulkan"} "\$@"
            EOF
            chmod +x $bin/nixgl-intel

            cat > $bin/nixgl-nvidia <<EOF
            #!/bin/sh
            glbin=\$(nix eval --quiet --raw --impure "${nixglPkgs}.nixGLNvidia.meta.name")
            vkbin=\$(echo \$glbin | sed s/GL/Vulkan/)
            exec nix shell --quiet --impure ${nixglPkgs}.nixGLNvidia ${nixglPkgs}.nixVulkanNvidia -c \$glbin \$vkbin "\$@"
            EOF
            chmod +x $bin/nixgl-nvidia

            cat > $bin/nvidia-offload <<EOF
            #!/bin/sh
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only
            exec "\$@"
            EOF
            chmod +x $bin/nvidia-offload

            cat > $bin/nixgl <<EOF
            #!/bin/sh
            if [ ! -h "${config.xdg.cacheHome}/nixgl/result" ]
            then
                mkdir -p "${config.xdg.cacheHome}/nixgl"
                nix build --quiet --impure \
                  --out-link "${config.xdg.cacheHome}/nixgl/result" \
                  ${nixglPkgs}.nixGLNvidia \
                  ${nixglPkgs}.nixVulkanNvidia
            fi

            if [ "\$__NV_PRIME_RENDER_OFFLOAD" = "1" ]
            then
                nixgl-nvidia "\$@"
            else
                nixgl-intel "\$@"
            fi
            EOF
            chmod +x $bin/nixgl
          '';
      })
    ];

    home.packages = [pkgs.gpu-wrappers];

    home.activation = {
      clearNixglCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
        [ -v DRY_RUN ] || rm -f ${config.xdg.cacheHome}/nixgl/result*
      '';
    };

    nixGLWrap = nixGLWrap;
  };
}
