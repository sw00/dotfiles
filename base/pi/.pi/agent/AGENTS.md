# Global rules

## Web search hygiene

Never include secrets, credentials, proprietary code, internal hostnames, or
client/project-identifying details in web search queries or fetched URLs.
Generalize first: search the library's error message, not your code; the
public concept, not the internal project name.

## Web retrieval routing

- Use `web_search` for discovery: queries, comparisons, recency-sensitive
  research, and finding candidate pages.
- Use `fetch_content` for reading a specific known URL. JS-heavy and
  e-commerce pages may be rendered through the configured Eyes/Firecrawl
  service; allow its bounded extraction/retry to work before giving up.
- Do not repeatedly retry an empty page result; treat it as bot-blocking or
  unavailable content and report that limitation.
- Do not pass `auth: true` or an auth-fetch profile unless the user explicitly
  requests authenticated browsing and a configured profile is known to exist.

## Agent skills location

Project skills live in the repo's `.agents/skills/` directory — the
cross-harness standard (agentskills.io), read by pi, Claude Code, Codex, and
others. Do NOT put project skills in `.pi/skills/` (pi-only; reserved for
none in practice). Follow the agentskills.io spec: `SKILL.md` with
`name`/`description` frontmatter, progressive disclosure, and paths relative
to the skill directory. When working on or creating a skill, look in
`.agents/skills/` first.