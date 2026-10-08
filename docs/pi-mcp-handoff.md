# Pi MCP integration handoff

> **Superseded in part (2026-10-08).** This document was written against pi
> 0.83.0 and concluded that pi had no native `mcpServers` configuration, so it
> proposes a bespoke TypeScript extension wrapping `mcpc`/`mcporter`. Pi 1.1.0
> ships native MCP: `mcp.json`, `pi mcp add|list|login|logout`, `/mcp`, OAuth
> with dynamic client registration, and `exposure`/`toolExposure` filtering.
> The curated read-only tool surface described below is now configuration
> rather than code, so treat the *staging and architecture* sections as
> historical. The endpoint, authentication, scope, version-pinning, and
> write-policy research below is still current and is why this document is
> kept.

**Status:** research complete; implementation deliberately not started
**Scope:** laptop-side pi integration for Linear and Grafana Cloud
**Date:** 2026-10-07

## Decision summary

Start with a read-only, laptop-only integration. Do not put Linear/work
credentials on non-laptop deployments and do not make work API calls from
non-laptop profiles.

Preferred staged approach:

1. Use **Apify `mcpc`** as the first transport/authentication prototype. It
   supports stdio and Streamable HTTP, OAuth 2.1, persistent sessions, JSON
   output, progressive tool discovery, OS-keychain credential storage, and a
   local proxy mode.
2. Evaluate **`mcporter`** as the likely long-term in-process integration. It
   is TypeScript-native, exposes a runtime as well as a CLI, supports OAuth,
   typed client generation, generated CLIs, tool include/exclude filtering,
   and a bridge/serve mode.
3. Keep **`f/mcptools`** as a manual diagnostic CLI. It is useful for
   inspecting and calling stdio/HTTP servers, but its current public material
   does not establish an equivalent OAuth/keychain story.

Do not begin with a generic `mcp_call(server, tool, arguments)` surface.
Expose a small, reviewed set of pi tools instead.

## Endpoints and authentication

### Linear

Use Linear's hosted MCP endpoint:

```text
https://mcp.linear.app/mcp
```

The older `/sse` endpoint is deprecated; use Streamable HTTP.

For interactive use, use OAuth/PKCE with the minimum scopes:

- Start with `read`.
- Add `issues:create` only when issue creation is needed.
- Add `comments:create` only when comments are needed.
- Avoid broad `write` and never request `admin` for this integration.
- Use the user actor so changes are attributable to the owner.

Linear's client-credentials flow is intended for server-to-server or scheduled
automation and produces an app actor token. It is not the default choice for
an interactive personal coding agent.

### Grafana Cloud

Prefer Grafana Cloud's hosted MCP server when available. It uses OAuth 2.1,
is fully managed, and applies the signed-in user's Grafana RBAC permissions.
Obtain the exact managed endpoint from Grafana Cloud rather than guessing it.

Use the self-hosted `mcp-grafana` server only if the hosted endpoint is not
available. In that case:

- Use a dedicated least-privilege service-account token.
- Pin a current fixed version. Grafana advisories list `>=0.17.1` as fixed for
  CVE-2026-15583 and `>=1.1.0` as fixed for CVE-2026-19516.
- Run over stdio where possible; do not expose an unauthenticated local HTTP
  listener.
- Use `--disable-write`.
- Use `--disable-api` to omit the broad `grafana_api_request` tool.
- Consider `--disable-proxied` if Tempo/proxied datasource tools are not
  required.

## Proposed pi shape

Pi 0.83.0 does not document a native `mcpServers` configuration. Its
extension API is the integration point: a TypeScript extension can register
custom tools, commands, lifecycle hooks, and dynamic tool activation.

Proposed commands:

```text
/work-connect
/work-disconnect
/work-tools
```

Connection rules:

- Do not connect to remote services during extension import/startup.
- Connect on `/work-connect` or on the first explicitly requested work tool.
- Keep MCP sessions in memory and close them on `session_shutdown`.
- Use the current turn's abort signal for HTTP/tool cancellation.
- Keep credentials in `mcpc`'s OS keychain or the reviewed MCP client's
  credential store; never place them in prompts, tool results, repository files,
  or project `.env` files.
- Use a pinned dependency/version and a lockfile.

Initial pi-facing tools:

```text
linear_search_issues
linear_get_issue
linear_get_project
linear_list_my_issues
linear_draft_issue
linear_draft_comment

grafana_query_metrics
grafana_query_logs
grafana_list_alerts
grafana_get_alert
grafana_search_dashboards
grafana_get_dashboard
```

The Grafana tools must impose bounded time ranges, result-size limits and
query timeouts. Linear searches must use bounded result counts and avoid
prefetching the whole workspace.

Treat issue descriptions, comments, logs, dashboards and alert annotations as
untrusted external data. They can contain prompt-injection text; they are data
to summarize, not instructions to follow.

## Write policy

### Linear

Start read-only. When writes are justified, use a two-step flow:

1. `linear_draft_*` returns a preview containing the target and exact changes.
2. A separate explicit owner approval applies the preview.

Do not allow automatic issue creation, status changes, assignments or comments
from an unconfirmed model turn.

### Grafana

Keep Grafana writes disabled initially. If a write workflow is later needed,
add one narrowly scoped operation at a time with a separate confirmation path.
Never expose a generic authenticated API request tool to the model.

## Why the other tools are not the first choice

- **`f/mcptools`:** good manual shell/debug tool; insufficiently clear OAuth and
  credential-storage story for hosted Linear/Grafana use.
- **Generic `mcp-proxy` aggregators:** useful when many servers create context
  pressure, but add a persistent process, config, lifecycle and credential
  boundary. Two servers do not justify one yet.
- **Supergateway:** transport bridge for stdio-to-HTTP; neither Linear nor the
  hosted Grafana endpoint needs that conversion. Use only for a deliberate
  self-hosted stdio fallback.
- **Large MCP/LLM hosts:** solve a broader problem than pi needs and would
  duplicate pi's model/tool orchestration.

## Implementation sequence

### Phase 0 — laptop validation

- Install a pinned `mcpc` version.
- Authenticate to Linear and Grafana Cloud from the laptop.
- Create named sessions.
- Inspect tools and record the exact read-only tool names.
- Test bounded issue, alert, metric and log reads.
- Confirm logout/revocation and token storage behaviour.

### Phase 1 — pi read-only extension

- Add one laptop-only extension or package.
- Register only the curated tools above.
- Prefer an in-process `mcporter` runtime if its OAuth/storage behaviour is
  acceptable; otherwise call a local `mcpc` proxy.
- Add connection status and clean shutdown.
- Test with a fixture/mock MCP server before live credentials.

### Phase 2 — Linear drafts

- Add preview/apply for issue and comment creation.
- Add explicit owner confirmation and an audit-friendly result containing the
  Linear URL/identifier.
- Keep the integration disabled by default outside the laptop profile.

### Phase 3 — selective writes

Only add a Grafana write or Linear status/assignment operation after a real
repeated workflow justifies it.

## References

- Pi local docs: `pi/docs/extensions.md`, `pi/docs/security.md`,
  `pi/docs/packages.md`, `pi/docs/mcp.md` (native MCP, added after this
  document was written)
- Apify mcpc: https://github.com/apify/mcp-cli
- MCPorter: https://github.com/openclaw/mcporter
- f/mcptools: https://github.com/f/mcptools
- Linear MCP changelog: https://linear.app/changelog/2026-02-05-linear-mcp-for-product-management
- Linear OAuth: https://linear.app/developers/oauth-2-0-authentication
- Grafana MCP servers: https://grafana.com/docs/grafana-cloud/ai-tools/mcp-servers/
- Grafana OSS MCP setup: https://grafana.com/docs/grafana-cloud/ai-tools/mcp-servers/oss-mcp/
- Grafana CVE-2026-15583: https://grafana.com/security/security-advisories/cve-2026-15583/
- Grafana CVE-2026-19516: https://grafana.com/security/security-advisories/cve-2026-19516/
