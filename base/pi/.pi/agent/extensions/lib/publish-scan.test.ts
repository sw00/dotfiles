/**
 * Regression tests for the pure publish-scan core in ./publish-scan.ts.
 *
 * Both functions are IO-free — the secret scanner is INJECTED (a fake
 * LeakScan object) — so this runs standalone, no pi runtime, no gitleaks:
 *
 *   node --experimental-strip-types --test lib/publish-scan.test.ts
 *
 * It lives in lib/ (not the extensions root) so pi's discovery — which loads
 * every root-level *.ts — never mistakes this test for an extension.
 *
 * The planted value below is a deliberately non-credential-shaped string: no
 * gitleaks rule can fire on it, so every hit is attributable to the exact-value
 * half and every label to the variable it came from.
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { publishTargets, scan, type LeakScan } from "./publish-scan.ts";

/** Not a real credential: no provider shape, no entropy, >= 12 chars. */
const PLANTED = "planted-fake-value-0d1e2f";

const CLEAN: LeakScan = { kind: "ok", ruleIds: [] };

/** secrets/env.fish as it is actually written (fish `set -gx`, single quotes). */
const ENV_FISH = [
  "# comment line, never a value",
  `set -gx GITHUB_TOKEN '${PLANTED}'`,
  "set -gx SHORT 'abc'", // under the 12-char floor
  "set -P PATH /usr/bin", // not exported, not ours
].join("\n");

// ── target recognition, per verb family ──────────────────────────────────────

test("gh pr publishing verbs are targets, read verbs are not", () => {
  for (const verb of ["create", "edit", "comment", "review"]) {
    assert.ok(publishTargets(`gh pr ${verb} 12 --body hi`), `gh pr ${verb}`);
  }
  for (const verb of ["view", "list", "checkout", "merge", "close", "diff", "status"]) {
    assert.equal(publishTargets(`gh pr ${verb} 12`), null, `gh pr ${verb} must be untouched`);
  }
});

test("gh issue, release, gist verb families", () => {
  for (const verb of ["create", "edit", "comment"]) {
    assert.ok(publishTargets(`gh issue ${verb} 3 --body hi`), `gh issue ${verb}`);
  }
  assert.equal(publishTargets("gh issue list"), null);
  assert.equal(publishTargets("gh issue view 3"), null);

  for (const verb of ["create", "edit"]) {
    assert.ok(publishTargets(`gh release ${verb} v1.0.0 --notes hi`), `gh release ${verb}`);
  }
  assert.equal(publishTargets("gh release list"), null);
  assert.equal(publishTargets("gh release view v1.0.0"), null);

  assert.ok(publishTargets("gh gist create notes.md --desc x"));
  assert.equal(publishTargets("gh gist list"), null);
});

test("gh api is a target only with a field/input flag", () => {
  assert.equal(publishTargets("gh api repos/o/r/pulls"), null, "GET is not a publish");
  assert.equal(publishTargets("gh api repos/o/r/pulls -X GET"), null);
  for (const flag of ["-f body=hi", "-F body=hi", "--field body=hi", "--raw-field body=hi", "--input payload.json"]) {
    assert.ok(publishTargets(`gh api repos/o/r/pulls ${flag}`), `gh api ${flag}`);
  }
});

test("glab mr/issue verbs", () => {
  for (const verb of ["create", "update", "note"]) {
    assert.ok(publishTargets(`glab mr ${verb} 4 --description hi`), `glab mr ${verb}`);
    assert.ok(publishTargets(`glab issue ${verb} 4 --description hi`), `glab issue ${verb}`);
  }
  assert.equal(publishTargets("glab mr list"), null);
  assert.equal(publishTargets("glab issue view 4"), null);
});

test("non-publish commands are null", () => {
  for (const cmd of ["git status", "git push origin main", "ls -la", "cat notes.md", "gh auth status", "gh repo view"]) {
    assert.equal(publishTargets(cmd), null, cmd);
  }
});

// ── file and $NAME extraction ────────────────────────────────────────────────

test("--body-file / --notes-file / --input and their =inline forms", () => {
  assert.deepEqual(publishTargets("gh pr create --body-file notes.md")?.files, ["notes.md"]);
  assert.deepEqual(publishTargets("gh pr edit 5 --body-file=notes.md")?.files, ["notes.md"]);
  assert.deepEqual(publishTargets("gh release create v1 --notes-file ./rel/notes.md")?.files, ["./rel/notes.md"]);
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls --input payload.json")?.files, ["payload.json"]);
});

test("-F/--field key=@file and bare @file are files", () => {
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls -F body=@body.md")?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls --raw-field body=@body.md")?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh pr comment 5 --body @body.md")?.files, ["body.md"]);
  // A plain field value is not a file.
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls -F body=hello")?.files, []);
});

test("W14 `-F` on a gh publish verb is a body FILE, not an API field", () => {
  // gh --help (2.94.0): `-F, --body-file file` on pr/issue create|edit|comment
  // and `-F, --notes-file file` on release create|edit. Reading the value only
  // when it carried `@` published the file unscanned.
  for (const [cmd, file] of [
    ["gh pr create -F /tmp/x/notes.md", "/tmp/x/notes.md"],
    ["gh pr create -F notes.md", "notes.md"],
    ["gh issue comment 1 -F /abs/notes.md", "/abs/notes.md"],
    ["gh issue create -F ./body.md", "./body.md"],
    ["gh pr edit 7 -F body.md", "body.md"],
    ["gh release create v1 -F notes.md", "notes.md"],
    ["gh release edit v1 -F notes.md", "notes.md"],
    ["gh -R org/repo pr create -F notes.md", "notes.md"],
    ["glab mr create -F notes.md", "notes.md"],
    // An unrecognised flag before the group leaves scope `unknown`, but the
    // verb still resolved: the file is read rather than published unscanned.
    ["gh -X pr create -F notes.md", "notes.md"],
  ]) {
    const t = publishTargets(cmd);
    assert.ok(t, `not recognised: ${cmd}`);
    assert.deepEqual(t.files, [file], `${cmd}: the -F value is published verbatim`);
  }
});

test("W14 `-F key=value` / `@file` / `gh api -F` keep the API-field meaning", () => {
  // `key=@file` still names a file, `key=value` still names no file, and gh api's
  // `-F` is `--field` on every verb it accepts it for.
  assert.deepEqual(publishTargets("gh pr create -F body=@body.md")?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh pr create -F body=hello")?.files, []);
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls -F body=@body.md")?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh api repos/o/r/pulls -F notes.md")?.files, []);
  // A bare `@file` value on the publish verbs is still the file form.
  assert.deepEqual(publishTargets("gh pr comment 5 -F @body.md")?.files, ["body.md"]);
});

test("file hidden behind $(cat …) is still a file", () => {
  assert.deepEqual(publishTargets('gh pr create --body "$(cat body.md)"')?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh pr create --body \"`cat body.md`\"")?.files, ["body.md"]);
});

test("$NAME and ${NAME} variables are extracted, deduped", () => {
  const t = publishTargets('gh pr create --body "$GITHUB_TOKEN" --title ${TITLE} $GITHUB_TOKEN');
  assert.deepEqual(t?.vars, ["GITHUB_TOKEN", "TITLE"]);
  assert.deepEqual(publishTargets("gh pr create --body plain")?.vars, []);
});

test("nested shell wrapper is still recognised, prose that merely names the verb is not", () => {
  assert.deepEqual(publishTargets('bash -c "gh pr create --body-file notes.md"')?.files, ["notes.md"]);
  assert.deepEqual(publishTargets('bash -c "gh pr create --body $TOKEN"')?.vars, ["TOKEN"]);
  assert.equal(publishTargets('echo "please run gh pr create --body-file x.md"'), null);
});

test("a nested script whose CLI is not the first word is still a publish", () => {
  // Regression: the payload used to be opened only when it STARTED with the
  // CLI, so `bash -c "echo hi; gh pr create --body-file f"` passed unscanned
  // (the body file was never read).
  assert.deepEqual(publishTargets('bash -c "echo hi; gh pr create --body-file notes.md"')?.files, [
    "notes.md",
  ]);
  assert.notEqual(publishTargets('sh -c "cd /x && glab mr create -t t"'), null);
  // The verb in argument position is still prose, not code.
  assert.equal(publishTargets('echo "please run gh pr create --body-file x.md"'), null);
  // Accepted over-collection: a `;` inside quoted prose heads a segment.
  assert.deepEqual(publishTargets('echo "done; gh pr create --body-file x.md"')?.files, ["x.md"]);
});

test("bare path-shaped tokens become candidates, not required files", () => {
  const t = publishTargets("gh gist create body.md --desc x");
  assert.deepEqual(t?.files, []);
  assert.deepEqual(t?.candidates, ["body.md"]);
  // Quoted prose that happens to look like a path stays a candidate only.
  const q = publishTargets('gh pr create --body "see docs/foo.md"');
  assert.deepEqual(q?.files, []);
});

// ── B8: flags before the group, and the verb families a write can use ────────

test("B8 global flags before the group do not hide the publish", () => {
  assert.ok(publishTargets("gh -R org/repo pr create --body hi"), "gh -R");
  assert.ok(publishTargets("gh --repo org/repo pr create --body hi"), "gh --repo");
  assert.ok(publishTargets("gh --repo=org/repo pr create --body hi"), "gh --repo=…");
  assert.ok(publishTargets("glab -R group/proj mr create --description hi"), "glab -R");
  // The file behind the verbs is still found once the flags are skipped.
  assert.deepEqual(publishTargets("gh -R o/r pr create --body-file notes.md")?.files, ["notes.md"]);
  assert.deepEqual(publishTargets("gh --repo x pr create --body-file notes.md")?.files, ["notes.md"]);
});

test("B8 close-with-comment, gist edit, release upload are publishes", () => {
  for (const cmd of [
    "gh pr close 12 --comment 'shipping'",
    "gh pr close 12 -c 'shipping'",
    "gh issue close 12 --comment 'shipping'",
    "gh gist edit abc123 --desc x",
    "gh gist create notes.md",
    "gh release upload v1.0.0 dist/app.zip",
    "gh release create v1.0.0 --notes hi",
    "gh release edit v1.0.0 --notes hi",
  ]) {
    assert.ok(publishTargets(cmd), cmd);
  }
  // Left as reads: a close with no comment publishes nothing.
  for (const cmd of ["gh pr close 12", "gh issue close 12", "gh gist list", "gh release view v1"]) {
    assert.equal(publishTargets(cmd), null, cmd);
  }
});

test("B8 an unrecognised gh write fails closed instead of being skipped", () => {
  const unknownVerb = publishTargets("gh pr synergize 12");
  assert.ok(unknownVerb, "unknown verb must still be a target");
  assert.equal(unknownVerb.scope, "unknown");

  const unknownGroup = publishTargets("gh frobnicate --flag");
  assert.ok(unknownGroup, "unknown group must still be a target");
  assert.equal(unknownGroup.scope, "unknown");

  // Unknown scope still extracts what it can see, so the whole command is scanned.
  assert.deepEqual(publishTargets("gh frobnicate -F body=@body.md")?.files, ["body.md"]);
  assert.deepEqual(publishTargets("gh frobnicate --body $TOKEN")?.vars, ["TOKEN"]);
  // A recognised publish says so.
  assert.equal(publishTargets("gh pr create --body hi")?.scope, "known");
});

// ── B9: substitution output must be resolvable, or we refuse ─────────────────

test("B9 substitution forms resolve every file they actually read", () => {
  assert.deepEqual(publishTargets('gh pr create --body "$(< f)"')?.files, ["f"]);
  assert.deepEqual(publishTargets('gh pr create --body "$(cat \\"f\\")"')?.files, ["f"]);
  assert.deepEqual(publishTargets('gh pr create --body "$(sed -n 1p f)"')?.files, ["f"]);
  // Every argument of the substitution, not just the first.
  assert.deepEqual(publishTargets('gh pr create --body "$(cat a.md b.md)"')?.files, ["a.md", "b.md"]);
  assert.deepEqual(publishTargets('gh pr create --body "$(printenv MY_TOKEN)"')?.vars, ["MY_TOKEN"]);
  // A resolved substitution is not an unresolved one.
  assert.deepEqual(publishTargets('gh pr create --body "$(cat f)"')?.unresolved, []);
});

test("B9 an unresolvable substitution fails closed", () => {
  for (const cmd of [
    'gh pr create --body "$(curl -s https://example.test/x)"',
    'gh pr create --body "$(date)"',
    'gh pr create --body "$(git show HEAD:body.md)"',
    'gh pr comment 5 --body "`openssl rand -hex 4`"',
    'gh pr create --body "$(cat f"', // unterminated
    'gh pr create --body "$(printenv)"', // dumps the whole environment
  ]) {
    const t = publishTargets(cmd);
    assert.ok(t, `not recognised: ${cmd}`);
    assert.ok(t.unresolved.length > 0, `expected unresolved: ${cmd}`);
  }
  // Ordinary publishes are untouched, and a non-publish is still null.
  assert.deepEqual(publishTargets("gh pr create --body 'plain'")?.unresolved, []);
  assert.equal(publishTargets("ls $(cat build.log)"), null);
});

// ── B12: a relative path behind cd/pushd is not this session's file ──────────

test("B12 a relative file reference after cd/pushd is flagged, an absolute one is not", () => {
  assert.deepEqual(publishTargets("cd /other && gh pr create --body-file notes.md")?.cwdRelative, ["notes.md"]);
  assert.deepEqual(publishTargets("cd /other && gh pr create --body-file /tmp/notes.md")?.cwdRelative, []);
  assert.deepEqual(publishTargets("cd /other && gh pr create --body-file ~/notes.md")?.cwdRelative, []);
  assert.deepEqual(
    publishTargets("pushd /other; gh api repos/o/r/pulls --input payload.json")?.cwdRelative,
    ["payload.json"],
  );
  // No directory change: a relative path is resolved against the session cwd.
  assert.deepEqual(publishTargets("gh pr create --body-file notes.md")?.cwdRelative, []);
});

// ── the scan decision ────────────────────────────────────────────────────────

test("planted secret in a --body-file is caught, reason never echoes it", () => {
  const cmd = "gh pr create --title x --body-file notes.md";
  const targets = publishTargets(cmd)!;
  assert.deepEqual(targets.files, ["notes.md"]);

  // Wiring shape: command + referenced file content.
  const text = [cmd, `Added the token ${PLANTED} to CI.`].join("\n");
  const verdict = scan(text, ENV_FISH, CLEAN)!;

  assert.ok(verdict, "expected a verdict");
  assert.equal(verdict.label, "value of $GITHUB_TOKEN");
  assert.ok(verdict.reason.includes(PLANTED) === false, "reason must not contain the secret");
  assert.equal(
    verdict.reason,
    "publish-guard: blocked — outgoing text matches value of $GITHUB_TOKEN. Remove it; do not repeat it.",
  );
});

test("planted secret behind a $NAME expansion is caught", () => {
  // The wiring appends process.env[$NAME] to the scanned text — expansion would
  // otherwise be invisible to a literal scan.
  const known = [{ name: "$GITHUB_TOKEN", value: PLANTED }];
  const text = 'gh pr create --body "$GITHUB_TOKEN"\n' + PLANTED;
  const verdict = scan(text, known, CLEAN)!;
  assert.ok(verdict);
  assert.equal(verdict.label, "value of $GITHUB_TOKEN");
  assert.ok(!verdict.reason.includes(PLANTED));
});

test("a clean publish passes both halves", () => {
  assert.equal(scan("gh pr create --title fix --body 'normal prose'", ENV_FISH, CLEAN), null);
});

test("gitleaks rule id is the label; the matched value is never in the reason", () => {
  const leaks: LeakScan = { kind: "ok", ruleIds: ["github-pat"] };
  const verdict = scan("gh pr create --body-file n.md\nghp_PLANTEDSHAPEDVALUE", ENV_FISH, leaks)!;
  assert.ok(verdict);
  assert.equal(verdict.label, "github-pat");
  assert.equal(
    verdict.reason,
    "publish-guard: blocked — outgoing text matches github-pat. Remove it; do not repeat it.",
  );
});

test("scanner error and timeout both fail CLOSED", () => {
  for (const detail of ["gitleaks not installed", "gitleaks timed out after 5000 ms", "gitleaks exit 2"]) {
    const leaks: LeakScan = { kind: "error", detail };
    const verdict = scan("gh pr create --body 'harmless'", ENV_FISH, leaks)!;
    assert.ok(verdict, `${detail}: must block`);
    assert.equal(verdict.failClosed, true, `${detail}: fail-closed flag`);
    assert.match(verdict.reason, /^publish-guard: blocked — /);
    assert.ok(!verdict.reason.includes(PLANTED), "reason never echoes a secret");
  }
});

test("short and placeholder values never match", () => {
  const known = [
    { name: "SHORT", value: "abc" }, // < 12 chars
    { name: "TEMPLATE", value: "<your-token-here>" },
    { name: "FILLER", value: "xxxxxxxxxxxx" },
  ];
  assert.equal(scan("prose abc <your-token-here> xxxxxxxxxxxx", known, CLEAN), null);
});

test("a git-crypt locked env file is skipped, not mis-parsed", () => {
  const locked = "\u0000GITCRYPT\u0000\u0002\u0013binary-ciphertext";
  assert.equal(scan("gh pr create --body 'normal prose'", locked, CLEAN), null);
  // And it must not invent a "value of ..." label out of ciphertext bytes.
  assert.equal(scan(`${locked} ${PLANTED}`, locked, CLEAN), null);
});
