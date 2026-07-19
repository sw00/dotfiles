/**
 * Infrastructure Safety Extension
 *
 * Live-infrastructure CLIs: aws, az, gcloud, kubectl, terraform/tofu.
 *
 *   locked – read-only: mutation commands are physically blocked
 *   armed  – write gate open: mutations allowed with confirmation
 *            (high-risk operations get a stronger confirmation)
 *
 * Commands: /infra-lock, /infra-arm
 * Tool:     infra_mode (mode "locked" | "armed"; for LLM self-regulation)
 *
 * Built on the shared engine in lib/mutation-guard.ts. If you want to gate
 * other tool domains (git, databases, package managers, ...), write a new
 * extension that imports createMutationGuard() with its own verb tables
 * and its own `domain` string — don't grow this file into a catch-all.
 * Different domains have different danger signals (SQL content, git
 * flags, etc.) that don't fit this CLI-verb-token model anyway.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createMutationGuard, execForContext, type ToolConfig } from "./lib/mutation-guard";

// ── aws ──────────────────────────────────────────────────────────
// Verb can appear anywhere in the token stream (service-verb-resource,
// e.g. `ec2 describe-instances`), so we scan all tokens.
const AWS: ToolConfig = {
  names: ["aws"],
  verbPosition: "any",
  mutation: new Set([
    // CRUD
    "create", "delete", "update", "put", "post", "patch",
    "add", "remove", "set", "unset", "reset",
    "replace", "modify", "edit", "truncate", "drop",
    // Lifecycle
    "run", "start", "stop", "restart", "reboot", "terminate",
    "launch", "shutdown", "poweroff", "halt",
    "suspend", "resume", "scale", "resize", "recreate",
    "provision", "decommission", "drain", "failover",
    // Networking
    "attach", "detach", "associate", "disassociate",
    "mount", "unmount", "connect", "disconnect",
    "register", "deregister", "subscribe", "unsubscribe",
    "bind", "unbind",
    // Storage
    "cp", "mv", "sync", "rm", "rb", "mb", "move", "copy",
    "upload", "download", "transfer", "push", "pull",
    "import", "export", "backup", "restore", "migrate",
    "purge", "flush", "empty", "clear",
    // Permissions
    "grant", "revoke", "allow", "deny", "assign", "unassign",
    "tag", "untag", "label", "annotate",
    // Deploy / config
    "apply", "deploy", "rollback", "release", "promote",
    "install", "uninstall", "upgrade", "downgrade", "rollout",
    "enable", "disable", "activate", "deactivate",
    "invoke", "execute", "exec", "call", "run-command",
    "trigger", "emit", "send", "publish", "commit", "merge",
    // Auth
    "login", "logout", "rotate",
    // Misc
    "format", "rename", "write", "append", "prepend",
    "cancel", "abort", "abandon", "evict",
  ]),
  read: new Set([
    "describe", "list", "get", "show", "display",
    "status", "history", "logs", "events",
    "help", "version", "usage", "info",
    "explain", "query", "whoami",
    "ls", "stat", "find", "search",
    "check", "validate", "verify", "test",
    "inspect", "audit", "review", "diff",
    "plan", "simulate", "estimate", "calculate",
    "summarize",
  ]),
  // Interactive shells / sessions into live resources: arbitrary code
  // execution, so treat like kubectl exec (always extra-strength confirm).
  highRisk: new Set(["start-session", "execute-command", "ssh"]),
};

// az and gcloud follow the same "verb anywhere" grammar as aws, and in
// practice the same verb vocabulary classifies them well too.
const AZ: ToolConfig = { ...AWS, names: ["az"] };
const GCLOUD: ToolConfig = { ...AWS, names: ["gcloud"] };

// ── kubectl ──────────────────────────────────────────────────────
// Verb is (almost) always the first token: `kubectl <verb> ...`. The
// exceptions are the "config" and "auth" command groups, where the real
// sub-verb is the second token (`config use-context`, `auth can-i`).
const KUBECTL: ToolConfig = {
  names: ["kubectl"],
  verbPosition: "first",
  groupPrefixes: new Set(["config", "auth", "rollout"]),
  alwaysRead: new Set([
    // "auth can-i <verb> <resource>" only checks a hypothetical
    // permission — it never performs the verb it's asking about, so
    // "auth can-i delete pods" must not be classified as a delete.
    "auth can-i",
  ]),
  read: new Set([
    "get", "describe", "logs", "top", "explain",
    "api-resources", "api-versions", "version", "cluster-info", "diff",
    "config view", "config current-context", "config get-contexts",
    // rollout status/history only report; restart/undo/pause/resume mutate
    "rollout status", "rollout history",
  ]),
  mutation: new Set([
    "create", "apply", "delete", "patch", "edit", "replace",
    "label", "annotate", "scale", "cordon", "uncordon",
    "drain", "taint", "expose", "set", "autoscale",
    "rollout restart", "rollout undo", "rollout pause", "rollout resume",
    // context-switching mutates *local* kubeconfig, but that silently
    // changes which cluster subsequent "read-only" commands target
    "config use-context", "config set-context", "config set-cluster",
    "config set-credentials", "config delete-context",
    "config delete-cluster", "config delete-user", "config rename-context",
  ]),
  // Not "mutations" in the CRUD sense — arbitrary code execution, file
  // transfer, or network tunnels into a live container. Always confirm.
  highRisk: new Set(["exec", "cp", "port-forward", "proxy", "attach", "debug"]),
  getContext: () => execForContext("kubectl", ["config", "current-context"]),
};

// ── terraform / tofu ───────────────────────────────────────────
// Same grammar and subcommands; tofu is a drop-in OpenTofu fork.
const TERRAFORM: ToolConfig = {
  names: ["terraform", "tofu"],
  verbPosition: "first",
  groupPrefixes: new Set(["state", "workspace"]),
  read: new Set([
    "plan", "validate", "show", "output", "fmt", "graph",
    "version", "providers", "get", "console",
    "state list", "state show",
    "workspace list", "workspace show",
  ]),
  mutation: new Set([
    "apply", "import", "taint", "untaint", "force-unlock",
    "init", "refresh", "login", "logout",
    "state rm", "state mv", "state push", "state replace-provider",
    "workspace new", "workspace delete", "workspace select",
  ]),
  // destroy is qualitatively worse than apply — extra-strength prompt
  highRisk: new Set(["destroy"]),
};

export default function (pi: ExtensionAPI) {
  createMutationGuard(pi, {
    domain: "infra",
    icon: "☁️",
    tools: [AWS, AZ, GCLOUD, KUBECTL, TERRAFORM],
  });
}
