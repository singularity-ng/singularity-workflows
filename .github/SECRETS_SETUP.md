# GitHub Secrets Setup

This document explains how to configure secrets for the Singularity-ng organization.

## Recommended Setup: Organization-Level Secrets

Add these secrets at the **organization level** to share across all repositories:

### Required Secrets

#### 1. CACHIX_AUTH_TOKEN
**What**: Authentication token for Cachix binary cache
**Where to get**: https://app.cachix.org/personal-auth-tokens
**Used by**:
- `.github/workflows/nix-ci.yml`
- `.github/workflows/cachix-push.yml`

**Setup**:
1. Go to https://app.cachix.org
2. Sign in with GitHub
3. Navigate to Personal Auth Tokens
4. Create new token with push access to `mikkihugo` cache
5. Copy token

#### 2. CLAUDE_CODE_OAUTH_TOKEN
**What**: OAuth token for Claude Code GitHub integration
**Where to get**: https://claude.ai (when setting up GitHub integration)
**Used by**:
- `.github/workflows/claude-review.yml`
- `.github/workflows/claude.yml`

**Setup**:
1. Install Claude Code GitHub App
2. Generate OAuth token from Claude settings
3. Copy token

#### 3. ORG_GITHUB_TOKEN (Optional but recommended)
**What**: GitHub Personal Access Token with org permissions
**Where to get**: https://github.com/settings/tokens
**Used by**:
- `.github/workflows/claude-review.yml` (for auto-merge)

**Setup**:
1. Create fine-grained PAT or classic PAT
2. Scopes needed: `repo`, `workflow`, `write:packages`
3. Copy token

**Note**: Falls back to `GITHUB_TOKEN` if not set, but has limited permissions.

#### 4. ANTHROPIC_API_KEY (Optional)
**What**: Anthropic API key for Claude API access
**Where to get**: https://console.anthropic.com
**Used by**:
- `.github/workflows/auto-pr.yml` (enhanced PR descriptions)

**Setup**:
1. Go to Anthropic Console
2. Create API key
3. Copy key

#### 5. CODECOV_TOKEN (Optional)
**What**: Codecov project token for coverage uploads
**Where to get**: https://codecov.io
**Used by**:
- `.github/workflows/ci.yml` (coverage job)

**Setup**:
1. Enable repo on Codecov
2. Get token from repo settings
3. Copy token

### Per-Repository Secrets

These should be added per-repository as needed:

#### HEX_API_KEY
**What**: Hex.pm publishing token
**Where to get**: https://hex.pm/settings/keys
**Used by**:
- `.github/workflows/publish.yml`

**Setup** (per Elixir repo):
1. Login to Hex.pm
2. Generate publishing key
3. Add to repository secrets

## Adding Organization Secrets

### Step 1: Navigate to Organization Settings

```
https://github.com/organizations/Singularity-ng/settings/secrets/actions
```

Or:
1. Go to https://github.com/Singularity-ng
2. Click "Settings"
3. Sidebar: "Secrets and variables" → "Actions"

### Step 2: Add Secrets

For each secret:

1. Click "New organization secret"
2. Enter **Name** (exactly as shown above, case-sensitive)
3. Enter **Value** (the token/key)
4. **Repository access**: Choose one:
   - ✅ **All repositories** (recommended for shared secrets)
   - Private repositories only
   - Selected repositories (choose specific repos)

### Step 3: Verify

After adding, workflows will automatically use organization secrets.

No code changes needed - workflows already reference these secrets!

## Security Best Practices

### Secret Rotation

Rotate secrets regularly:
- CACHIX_AUTH_TOKEN: Annually
- CLAUDE_CODE_OAUTH_TOKEN: When compromised or annually
- GITHUB_TOKEN: Auto-rotates (don't store)
- API keys: Every 6-12 months

### Access Control

For sensitive secrets (like HEX_API_KEY):
- Use "Selected repositories" access
- Only give to repos that need it
- Review access quarterly

### Monitoring

Check secret usage:
1. Go to organization secrets page
2. Click on a secret
3. View "Last used" timestamp
4. Review which repos are using it

## Troubleshooting

### "Secret not found" error

1. Check secret name is exactly correct (case-sensitive)
2. Verify workflow has access to org secrets
3. Check repository access settings for the secret

### Permission denied

1. Verify `CACHIX_AUTH_TOKEN` has push permissions
2. Check `ORG_GITHUB_TOKEN` has required scopes
3. Ensure secrets aren't expired

### Cache not working

1. Verify `CACHIX_AUTH_TOKEN` is set
2. Check cache name matches: `mikkihugo`
3. Test with: `cachix push mikkihugo result`

## Testing Secrets

After adding org secrets, test with:

```bash
# Trigger a workflow manually
gh workflow run nix-ci.yml

# Check workflow logs
gh run list --workflow=nix-ci.yml
gh run view <run-id> --log
```

Look for:
- ✅ "Setup Cachix" step succeeds
- ✅ "Push to Cachix" completes without auth errors
- ✅ No "secret not found" errors

## Enterprise Secrets

If you have **GitHub Enterprise**, you can set enterprise-level secrets:

```
https://github.com/enterprises/YOUR_ENTERPRISE/settings/secrets/actions
```

Enterprise secrets cascade to:
- All organizations in the enterprise
- All repositories in those organizations

Use enterprise secrets for:
- Company-wide infrastructure (Cachix, monitoring, etc.)
- Security tools (Sobelow, SAST, etc.)
- Common CI/CD tools

## Secret Priority

GitHub checks secrets in this order:
1. Repository secrets (highest priority)
2. Organization secrets
3. Enterprise secrets

This allows per-repo overrides when needed.

## Summary Checklist

Organization-level (add once):
- [ ] CACHIX_AUTH_TOKEN
- [ ] CLAUDE_CODE_OAUTH_TOKEN
- [ ] ORG_GITHUB_TOKEN (optional)
- [ ] ANTHROPIC_API_KEY (optional)
- [ ] CODECOV_TOKEN (optional)

Repository-level (per Elixir repo):
- [ ] HEX_API_KEY

After setup:
- [ ] Test nix-ci.yml workflow
- [ ] Verify Cachix pushes work
- [ ] Test Claude workflows (@claude mention)
- [ ] Document any repo-specific secrets

---

**Need help?** Check GitHub docs:
https://docs.github.com/en/actions/security-guides/encrypted-secrets
