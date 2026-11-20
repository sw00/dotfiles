# Global rules

## Web search hygiene

Never put secrets, credentials, proprietary code, internal hostnames, or
client/project-identifying details into search queries or fetched URLs.
Generalize first: the library's error message, not your code; the public
concept, not the internal project name.

## Web retrieval routing

`web_search` for discovery — queries, comparisons, recency-sensitive research.
`fetch_content` for a known URL; JS-heavy pages may render through the
Eyes/Firecrawl service, so let its bounded retry work before giving up. An empty
fetch result means bot-blocking: report it, do not retry. Pass `auth: true` only
on an explicit user request with a known profile.

## Agent skills location

Project skills live in `.agents/skills/` — the cross-harness agentskills.io
standard (pi, Claude Code, Codex all read it) — never `.pi/skills/`. Follow the
spec: `SKILL.md` with `name`/`description` frontmatter, progressive disclosure,
paths relative to the skill directory.

User-scope skills (every project) live in `~/.agents/skills`, installed with
`npx -y skills@latest add <source> -s <name> -g -a pi --copy -y`. They are copied,
not linked, and they run with full agent permissions — read one before you trust
it. Provenance is the host-local `~/.agents/.skill-lock.json` (source + commit
per skill); `check.sh` fails on a directory with no lock entry and no Paseo
owner, and the pinned commit is what makes the set reproducible.

## Process safety

Before killing a process, walk the ancestry from `$$`: if the target is your own
parent, say what the kill takes down (this session, its tmux server) and let the
user choose rather than killing it yourself.
