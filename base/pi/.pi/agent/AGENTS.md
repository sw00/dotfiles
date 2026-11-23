# Global rules

## Web search hygiene

Never put secrets, proprietary code, internal hostnames, or client-identifying
details into search queries or fetched URLs. Generalize first: the library's
error, not your code; the public concept, not the project.

## Web retrieval routing

`fetch_content` for a known URL; empty = bot-blocking, report it, don't
retry. `auth: true` only on explicit request.

## Agent skills location

Project skills: `.agents/skills/` (the agentskills.io standard pi, Claude
Code and Codex all read), never `.pi/skills/`; `SKILL.md` with `name`/`description`
frontmatter.

## Process safety

Before killing a process, walk ancestry from `$$`. If it is your own parent,
say what dies with it (this session, its tmux server) and let the user choose.

## Waiting on long-running work

One blocking call (`gh run watch --exit-status`), never a `sleep` loop; never
wait in an expensive-model session.
