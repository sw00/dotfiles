# TokenTelemetry — on-demand AI coding usage dashboard

`tt up` / `tt down` — that's it.

## Quick start

```bash
tt up        # start TokenTelemetry (first run pulls images — ~1 min)
tt status    # check if running
tt down      # stop
```

Dashboard: http://localhost:13000

## Subcommands

| Command | What it does |
|---|---|
| `tt up` | Pull images if missing, create data dir, start containers |
| `tt down` | Stop and remove containers (data persists) |
| `tt restart` | Down then up |
| `tt logs` | Tail compose logs |
| `tt ps` | Show running services |
| `tt status` | Show container status + dashboard URL if running |
| `tt update` | Pull latest images, record new digests, recreate containers |

## Data

Everything lives in `~/.local/share/tokentelemetry/` on the host.
Containers can be removed; the data stays.  Back it up like any other
`$XDG_DATA_HOME` directory.

## Agent configuration

By default `~/.pi` is mounted read-only.  To track more agents (Claude
Code, Codex, Gemini CLI, etc.), edit `~/.config/tokentelemetry/compose.pi.yml`
and uncomment the relevant volume lines, then `tt restart`.

## Updating

```bash
tt update    # pulls :latest, records new @sha256: digests in env.tt
```

Commit the updated `env.tt` to lock in the new digests across machines.

## Uninstall

```bash
tt down
rm -rf ~/.local/share/tokentelemetry   # data (optional)
# The stow package is managed by your dotfiles — stow -D to unlink.
```
