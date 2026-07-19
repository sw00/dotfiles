/**
 * Regression tests for the pure classification logic in ./classify.ts,
 * exercised against the tool configs mirrored from infra-safety.ts.
 *
 * ./classify.ts has zero pi dependencies, so this runs standalone with
 * plain node/tsx — no pi runtime install required:
 *
 *   npx tsx base/pi/.pi/agent/extensions/lib/mutation-guard.test.ts
 *
 * Keep this file in sync whenever verb tables or classify()/findInvocations()
 * change — every bug found in review should leave a case here.
 */

import { classify, findInvocations, hasDryRun, type ToolConfig } from "./classify.ts";

// ── tool configs (kept in sync with infra-safety.ts) ─────────────
const AWS_MUTATION = new Set([
  "create", "delete", "update", "put", "post", "patch", "add", "remove", "set", "unset", "reset",
  "replace", "modify", "edit", "truncate", "drop", "run", "start", "stop", "restart", "reboot",
  "terminate", "launch", "shutdown", "poweroff", "halt", "suspend", "resume", "scale", "resize",
  "recreate", "provision", "decommission", "drain", "failover", "attach", "detach", "associate",
  "disassociate", "mount", "unmount", "connect", "disconnect", "register", "deregister",
  "subscribe", "unsubscribe", "bind", "unbind", "cp", "mv", "sync", "rm", "rb", "mb", "move",
  "copy", "upload", "download", "transfer", "push", "pull", "import", "export", "backup",
  "restore", "migrate", "purge", "flush", "empty", "clear", "grant", "revoke", "allow", "deny",
  "assign", "unassign", "tag", "untag", "label", "annotate", "apply", "deploy", "rollback",
  "release", "promote", "install", "uninstall", "upgrade", "downgrade", "rollout", "enable",
  "disable", "activate", "deactivate", "invoke", "execute", "exec", "call", "run-command",
  "trigger", "emit", "send", "publish", "commit", "merge", "login", "logout", "rotate", "format",
  "rename", "write", "append", "prepend", "cancel", "abort", "abandon", "evict",
]);
const AWS_READ = new Set([
  "describe", "list", "get", "show", "display", "status", "history", "logs", "events", "help",
  "version", "usage", "info", "explain", "query", "whoami", "ls", "stat", "find", "search",
  "check", "validate", "verify", "test", "inspect", "audit", "review", "diff", "plan", "simulate",
  "estimate", "calculate", "summarize",
]);
const AWS: ToolConfig = {
  names: ["aws"],
  verbPosition: "any",
  mutation: AWS_MUTATION,
  read: AWS_READ,
  highRisk: new Set(["start-session", "execute-command", "ssh"]),
};
const AZ: ToolConfig = { ...AWS, names: ["az"] };
const GCLOUD: ToolConfig = { ...AWS, names: ["gcloud"] };

const KUBECTL: ToolConfig = {
  names: ["kubectl"],
  verbPosition: "first",
  groupPrefixes: new Set(["config", "auth", "rollout"]),
  alwaysRead: new Set(["auth can-i"]),
  read: new Set([
    "get", "describe", "logs", "top", "explain", "api-resources", "api-versions", "version",
    "cluster-info", "diff", "config view", "config current-context", "config get-contexts",
    "rollout status", "rollout history",
  ]),
  mutation: new Set([
    "create", "apply", "delete", "patch", "edit", "replace", "label", "annotate", "scale",
    "cordon", "uncordon", "drain", "taint", "expose", "set", "autoscale", "rollout restart",
    "rollout undo", "rollout pause", "rollout resume", "config use-context", "config set-context",
    "config set-cluster", "config set-credentials", "config delete-context",
    "config delete-cluster", "config delete-user", "config rename-context",
  ]),
  highRisk: new Set(["exec", "cp", "port-forward", "proxy", "attach", "debug"]),
};

const TERRAFORM: ToolConfig = {
  names: ["terraform", "tofu"],
  verbPosition: "first",
  groupPrefixes: new Set(["state", "workspace"]),
  read: new Set([
    "plan", "validate", "show", "output", "fmt", "graph", "version", "providers", "get",
    "console", "state list", "state show", "workspace list", "workspace show",
  ]),
  mutation: new Set([
    "apply", "import", "taint", "untaint", "force-unlock", "init", "refresh", "login", "logout",
    "state rm", "state mv", "state push", "state replace-provider", "workspace new",
    "workspace delete", "workspace select",
  ]),
  highRisk: new Set(["destroy"]),
};

const TOOLS = [AWS, AZ, GCLOUD, KUBECTL, TERRAFORM];
const ALL_NAMES = new Set(TOOLS.flatMap((t) => t.names));
const BY_NAME = new Map<string, ToolConfig>();
for (const t of TOOLS) for (const n of t.names) BY_NAME.set(n, t);

type Verdict = "not-cloud" | "allow(read)" | "BLOCK(mutation)" | "BLOCK(high-risk)" | "BLOCK(unknown)";

function classifyCommand(cmd: string): Verdict {
  const invs = findInvocations(cmd, ALL_NAMES);
  if (invs.length === 0) return "not-cloud";
  let verdict: Verdict = "allow(read)";
  for (const inv of invs) {
    const tool = BY_NAME.get(inv.cli)!;
    if (hasDryRun(inv.fullCommand)) continue;
    const r = classify(tool, inv.tokens);
    if (r.kind === "mutation") return r.highRisk ? "BLOCK(high-risk)" : "BLOCK(mutation)";
    if (r.kind === "unknown") verdict = "BLOCK(unknown)";
  }
  return verdict;
}

// ── cases ──────────────────────────────────────────────────────
const cases: Array<[string, string]> = [
  // basic read/mutation across the three cloud CLIs
  ["aws s3 ls s3://bucket", "allow"],
  ["aws ec2 describe-instances", "allow"],
  ["az vm list", "allow"],
  ["gcloud compute instances list", "allow"],
  ["aws ec2 terminate-instances --instance-ids i-123", "BLOCK(mutation)"],
  ["aws s3 rb s3://bucket", "BLOCK(mutation)"],
  ["az vm delete --name foo -g bar", "BLOCK(mutation)"],
  ["gcloud compute instances delete vm-1 --zone us-central1", "BLOCK(mutation)"],
  ["gcloud pubsub topics publish my-topic --message hi", "BLOCK(mutation)"],

  // parsing robustness
  ["echo $(aws ec2 terminate-instances --instance-ids i-1)", "BLOCK(mutation)"],
  ["aws foo list --force delete-item", "BLOCK(mutation)"],
  ["/usr/local/bin/aws s3 rb s3://bucket", "BLOCK(mutation)"],
  ["aws ec2 describe-instances | xargs aws ec2 stop-instances", "BLOCK(mutation)"],
  ["aws ec2 describe-instances\nkubectl delete pod foo", "BLOCK(mutation)"],
  ["aws ec2 describe-instances $(kubectl delete pod foo)", "BLOCK(mutation)"],
  ["echo $(gcloud compute instances delete vm)", "BLOCK(mutation)"],
  ["gcloud frobnicate widgets", "BLOCK(unknown)"],
  ["ls -la /tmp", "not-cloud"],
  ["git status", "not-cloud"],

  // dry-run handling — =none must NOT bypass (it means "for real")
  ["aws ec2 run-instances --dry-run --image-id ami-1", "allow"],
  ["kubectl delete pod foo --dry-run=none", "BLOCK(mutation)"],
  ["kubectl delete pod foo --dry-run=client", "allow"],
  ["kubectl apply -f d.yaml --dry-run=server", "allow"],
  ["kubectl delete pod foo --dry-run", "allow"],

  // kubectl grammar: verb-first, config/auth groups
  ["kubectl get pods", "allow"],
  ["kubectl delete pod foo", "BLOCK(mutation)"],
  ["kubectl apply -f deploy.yaml", "BLOCK(mutation)"],
  ["kubectl config view", "allow"],
  ["kubectl config use-context prod", "BLOCK(mutation)"],
  ["kubectl auth can-i get pods", "allow"],
  ["kubectl auth can-i delete pods", "allow"], // must not read "delete" as the real verb
  ["kubectl rollout status deployment/foo", "allow"],
  ["kubectl rollout history deployment/foo", "allow"],
  ["kubectl rollout restart deployment/foo", "BLOCK(mutation)"],
  ["kubectl rollout undo deployment/foo", "BLOCK(mutation)"],

  // kubectl high-risk tier
  ["kubectl exec -it my-pod -- /bin/bash", "BLOCK(high-risk)"],
  ["kubectl cp my-pod:/etc/passwd ./passwd", "BLOCK(high-risk)"],
  ["kubectl port-forward svc/foo 8080:80", "BLOCK(high-risk)"],

  // terraform / tofu
  ["terraform plan", "allow"],
  ["terraform apply", "BLOCK(mutation)"],
  ["terraform destroy", "BLOCK(high-risk)"],
  ["terraform state list", "allow"],
  ["terraform state rm aws_instance.foo", "BLOCK(mutation)"],
  ["terraform workspace select prod", "BLOCK(mutation)"],
  ["terraform init", "BLOCK(mutation)"],
  ["terraform refresh", "BLOCK(mutation)"],
  ["tofu init -upgrade", "BLOCK(mutation)"],

  // interactive cloud shells are high-risk, not plain mutations
  ["aws ssm start-session --target i-123", "BLOCK(high-risk)"],
  ["aws ecs execute-command --cluster c --command /bin/sh", "BLOCK(high-risk)"],
  ["gcloud compute ssh my-vm", "BLOCK(high-risk)"],
  ["aws ec2 start-instances --instance-ids i-1", "BLOCK(mutation)"], // start != start-session

  // verb-shape filter avoids false positives from flag values
  ["aws ssm get-parameter --name /app/config/run", "allow"],
  ["aws ec2 describe-instances --filters Name=tag:delete,Values=x", "allow"],
];

let pass = 0;
let fail = 0;
for (const [cmd, expected] of cases) {
  const got = classifyCommand(cmd);
  const ok = got === expected || got.includes(expected);
  console.log(`${ok ? "✓" : "✗"}  ${got.padEnd(18)} | ${cmd.replace(/\n/g, " ⏎ ")}`);
  ok ? pass++ : fail++;
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
