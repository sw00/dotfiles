# Waiting on long-running processes

Applies to anything the agent cannot finish in one call: CI runs, deploys, long
test suites, a service reaching its first healthy state.

## The rule

**One blocking call, sized to the whole wait.** Never a `sleep`-and-check loop.

```bash
gh run watch --exit-status                 # or: gh pr checks --watch
fly watch --app <app>                      # or: fly status --wait
until <condition>; do sleep 10; done       # inside one call, no timeout cap
```

Pass an explicit `timeoutMs` when the wait can outlast the shell tool's default
(hypa's default is 30 s). `timeoutMs: 900000` is in the normal range for a CI
wait; re-watch when it expires rather than shortening the wait.

The cost lives in the **number of requests**, not the sleep itself: each poll is
a full model turn that resends the whole conversation. One wait that takes
twelve polls is twelve requests; a watcher makes it one.

## Why a long sleep is the worst case

A re-entry after roughly 5 minutes reprices the whole context uncached, and the
penalty multiplies with context size and model price.

Measured cache-hit rate against time since the previous request in the same
session (20,243 samples, `~/.pi/agent/sessions`, Oct–Nov):

| gap since previous request | deepseek-v4.1-flash | glm-5.3 |
|---|---|---|
| < 30 s | 99 % | 99 % |
| 120–180 s | 96 % | 89 % |
| 240–300 s | 95 % | 80 % |
| 300–360 s | 96 % | 67 % |
| 480–600 s | 93 % | 43 % |
| 600–900 s | 93 % | 15 % |
| 1200–1800 s | 95 % | 0 % |
| 1800 s + | 52 % | 0 % |

Effective cache lifetime: **~1800 s** for deepseek-v4.1-flash, **~240–300 s**
for glm-5.3. Both providers (`opencode-go`, `opencode`) behave identically for
the same model — the curve is a property of the model, not the route.

Cost per request on glm-5.3 at 220–300 k prompts: `$0.066` warm (< 60 s) →
`$0.11` (180–300 s) → `$0.21` (300–480 s) → `$0.32` (600–900 s) → `$0.41` (900 s+).

Consequence: **never park a wait in a session running a high-reasoning or
expensive model.** 18 of the 48 sub-300 s-gap glm-5.3 requests in the sample were
explicit `sleep` calls of 300–595 s — the model was budgeting for a 10-minute
cache lifetime that does not exist. Do the waiting on the cheap default model,
or outside the session entirely (tmux pane + `settle-notify`).

## What is not worth building

Both were evaluated against a month of logs and rejected; keep the reasoning if
either is proposed again.

**Declaring `promptCache` so the cache warmer covers waits.** pi's `CacheWarmer`
decides afresh at each refresh and never counts refreshes already spent, so its
cost per wait is unbounded. Break-even is `(input − cacheRead) / cacheRead` ≈
**4.4 refreshes** (~20 min at a 270 s TTL); a 60-minute blocking watcher gets
~13 refreshes, costing more than the single miss it prevents. It also lands
certain spend inside the same rolling window that caps the subscription.

**A tool-call guard that denies long `sleep`s.** 90 % of cold gaps in the sample
are isolated single runs rather than poll loops, so collapsing every loop would
save at most ~$6/month on glm-5.3 — and a denominator change (compaction) is
worth 4–10× more. A short-sleep loop also stays cache-warm and costs no more
than the block it evades, so the guard changes little beyond adding a way to
fail.

**The lever that does work** is per-model compaction
(`compaction.modelOverrides["opencode-go/glm-5.3"].reserveTokens`), which caps
the prompt size every request repurchases — see the `compaction` block in
`base/pi/.pi/agent/settings.desired.json`.
