# Nix Caching Setup

This repository uses **5 free caching layers** for maximum performance and availability.

## Multi-Cache Strategy

The flake automatically tries caches in order:
1. **cache.nixos.org** (official, always first)
2. **nix-community.cachix.org** (community cache, high hit rate)
3. **cache.garnix.io** (Garnix CI cache, automatic builds)
4. **mikkihugo.cachix.org** (our cache)
5. **Magic Nix Cache** (GitHub Actions only)

All caches are **FREE** and configured automatically!

## Caching Layers

### 1. Nix Community Cache
**Public cache**: `nix-community.cachix.org`

- **Free**: Unlimited usage
- **High hit rate**: Common Nix packages cached
- **Fast**: CDN-backed
- **Auto-configured** in flake.nix

No setup needed - already configured!

### 2. Garnix Cache
**Public cache**: `cache.garnix.io`

- **Free**: Unlimited usage
- **Automatic**: Builds all flake outputs
- **No config**: Just enable Garnix on GitHub
- **Dashboard**: https://garnix.io

Enable at: https://garnix.io (GitHub App)

Configuration: `garnix.yaml` (root of repo)

### 3. Cachix (Org Cache)
**Public cache**: `singularity-ng`

Stores:
- Built Nix derivations
- Development shells
- All package outputs

**Setup for users:**
```bash
# Install cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Use the cache
cachix use singularity-ng
```

Or already configured in flake.nix!

### 4. Magic Nix Cache
**GitHub Actions**: Automatic caching via `magic-nix-cache-action`

Benefits:
- Zero configuration
- Automatic cache invalidation
- Works across workflow runs
- Free for public repos
- ~90% cache hit rate

### 5. FlakeHub
**Flake registry**: Published flake for easy consumption

Use in your `flake.nix`:
```nix
{
  inputs = {
    singularity-workflows.url = "https://flakehub.com/f/Singularity-ng/singularity-workflows/*.tar.gz";
  };
}
```

## CI Workflows

### nix-ci.yml
Full Nix-based CI:
- Uses DeterminateSystems/nix-installer-action
- Integrates Cachix + Magic Nix Cache
- Runs tests in nix develop shell
- ~2-3 minutes (cached)

### cachix-push.yml
Weekly cache refresh:
- Rebuilds all derivations
- Pushes to Cachix
- Runs on schedule + manual trigger
- Keeps cache warm

### flakehub-publish.yml
FlakeHub publishing:
- Triggered on version tags
- Makes flake available via FlakeHub
- Easy consumption for users

## Cache Performance

**First build (cold cache):**
- ~5-8 minutes (downloads everything)

**Subsequent builds (warm cache):**
- ~1-2 minutes (everything cached)

**With Cachix:**
- Dev shell: ~30s (pull from cache)
- Full build: ~1-2 minutes

## Secrets Required

Setup in GitHub repository secrets:

1. `CACHIX_AUTH_TOKEN`
   - Get from: https://app.cachix.org
   - Needed for: cachix-push.yml

2. FlakeHub (optional)
   - Automatic via GitHub App
   - Or set `FLAKEHUB_TOKEN`

## Local Development

The flake includes Cachix configuration:

```nix
nixConfig = {
  extra-substituters = [ "https://mikkihugo.cachix.org" ];
  extra-trusted-public-keys = [ "mikkihugo.cachix.org-1:key" ];
};
```

This is automatically applied when you run:
```bash
nix develop
```

## Monitoring

- Cachix dashboard: https://app.cachix.org/cache/singularity-ng
- FlakeHub page: https://flakehub.com/flake/Singularity-ng/singularity-workflows
- GitHub Actions: Check workflow runs for cache hit rates

## Best Practices

1. **Weekly cache updates**: Scheduled via cachix-push.yml
2. **Lock file updates**: Keep flake.lock current for security
3. **Cache warming**: Run cachix-push after major dependency updates
4. **Monitor size**: Large caches cost more on Cachix (free tier: 10GB)

## Troubleshooting

### Cache misses
```bash
# Clear local Nix store cache
nix-collect-garbage -d

# Rebuild with fresh cache
nix develop --refresh
```

### Cachix authentication
```bash
# Re-authenticate
cachix authtoken <YOUR_TOKEN>

# Test push
nix build .#devShells.x86_64-linux.default
cachix push singularity-ng result
```

### FlakeHub updates not visible
- Check workflow runs in Actions tab
- Verify tag format: `v*` (e.g., v0.1.6)
- Check FlakeHub dashboard for errors

## Cost Considerations

- **Cachix free tier**: 10GB storage, unlimited downloads
- **Magic Nix Cache**: Free (GitHub Actions feature)
- **FlakeHub**: Free for public flakes

If cache exceeds 10GB:
- Consider paid Cachix plan
- Or switch to self-hosted cache (nixserve, S3)
