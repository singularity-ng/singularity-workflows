# Cachix configuration for singularity-workflows
# This file is used by cachix-action in CI
{
  name = "singularity-ng";

  # Public cache - anyone can read
  public = true;

  # What to push to the cache
  # We want to cache all our build outputs
  filter = {
    # Push all derivations
    derivations = true;

    # Don't push source derivations (saves space)
    source = false;
  };

  # Compression settings
  compression = "zstd";

  # Cache configuration for users
  instructions = ''
    # To use this cache, add to your nix.conf or use cachix:

    # Option 1: Using cachix CLI
    cachix use singularity-ng

    # Option 2: Manual nix.conf configuration
    # Add to /etc/nix/nix.conf or ~/.config/nix/nix.conf:
    substituters = https://cache.nixos.org https://mikkihugo.cachix.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mikkihugo.cachix.org-1:your-signing-key-here

    # Option 3: In your flake.nix
    nixConfig = {
      extra-substituters = [ "https://mikkihugo.cachix.org" ];
      extra-trusted-public-keys = [ "mikkihugo.cachix.org-1:your-signing-key-here" ];
    };
  '';
}
