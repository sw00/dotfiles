# TokenTelemetry — upstream provenance

- **Repository**: https://github.com/VasiHemanth/tokentelemetry
- **License**: MIT
- **Website**: https://tokentelemetry.com
- **Docs**: https://tokentelemetry.com/docs

## Image publish workflow

Pre-built container images are published to GitHub Container Registry (GHCR)
by CI on every push to `main`:

- `ghcr.io/vasihemanth/tokentelemetry-backend:latest`
- `ghcr.io/vasihemanth/tokentelemetry-frontend:latest`

Workflow: `.github/workflows/container-publish.yml` in the upstream repo.

## Why this isn't in Brewfile-base / ensure_system_tools

TokenTelemetry runs inside Docker containers — it is not a system-level
package. Docker (colima) is already provisioned by the dotfiles.  The images
are fetched at runtime by `tt up`, not by a package manager.  No brew/apt/dnf
entry is needed.

## How to update image digests

```bash
tt update
```

This pulls `:latest`, records the new `@sha256:` digests in `env.tt`, and
recreates the containers.  Commit the updated `env.tt` to lock in the new
digests.

## Agent directory mounts

By default only `~/.pi` is mounted (read-only).  To add more agents, edit
`compose.pi.yml` and uncomment the relevant volume entries, then run
`tt restart`.  No rebuild needed — the compose file is bind-mounted at
startup.
