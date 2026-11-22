/**
 * Infra CLI verb tables — pure data, ZERO pi deps.
 *
 * Single source of truth for the aws/az/gcloud/kubectl/terraform verb
 * classifications, imported by BOTH:
 *   - infra-safety.ts     (wires them into createMutationGuard)
 *   - mutation-guard.test.ts (regression tests, run under node --test)
 *
 * Keeping the tables here (not in infra-safety.ts) lets the test import them
 * without pulling in the pi runtime — classify.ts is likewise pi-free, and
 * ToolConfig is a plain data type. The only pi-wired field, KUBECTL.getContext,
 * is deliberately NOT set here; infra-safety.ts composes it back on with a
 * spread so this module stays import-clean under --experimental-strip-types.
 */

import type { ToolConfig } from "./classify.ts";

// ── aws ──────────────────────────────────────────────────────────
// Verb can appear anywhere in the token stream (service-verb-resource,
// e.g. `ec2 describe-instances`), so we scan all tokens.
export const AWS: ToolConfig = {
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
  // The credential-disclosing verbs belong here for the same reason: they hand
  // over material, not metadata (see secretNouns + classify.disclosesSecret).
  highRisk: new Set([
    "start-session", "execute-command", "ssh",
    // Secrets Manager / ECR / STS / KMS — verb reads, material out
    "get-secret-value", "batch-get-secret-value",
    "get-login-password", "get-authorization-token", "decrypt",
    // STS session/federation tokens: a credential by definition.
    "get-session-token", "get-federation-token", "assume-role-with-saml",
    // EKS bearer token for the cluster API.
    "get-token",
    // Parameter Store: the plural form hands back stored values in one call.
    // The singular form is flag-gated below (it returns ciphertext unless
    // --with-decryption is given) so ordinary config reads stay read-only.
    "get-parameters",
  ]),
  // Read verbs that disclose material only with the flag that asks for it.
  highRiskFlags: [
    { verb: "get-parameter", flags: ["--with-decryption"] },
    // Same disclosure, different shapes: a by-path query and the history of a
    // parameter both return the value once --with-decryption asks for it.
    { verb: "get-parameters-by-path", flags: ["--with-decryption"] },
    { verb: "get-parameter-history", flags: ["--with-decryption"] },
  ],
  // Nouns whose content is a credential. A read verb aimed at one of these is
  // high-risk even when the verb's root sits in the read set.
  //
  // The secretsmanager SERVICE NAME is deliberately NOT here: it is on every
  // aws secretsmanager command line, so listing it made metadata reads
  // (`describe-secret`, `list-secret-version-ids`) high-risk. What hands out
  // material is the verb, and those verbs sit in highRisk above.
  secretNouns: new Set([
    "secret", "secrets",
    // `aws configure get <key>` prints the stored credential itself.
    "aws_secret_access_key", "aws_session_token",
  ]),
};

// az and gcloud follow the same "verb anywhere" grammar as aws, and in
// practice the same verb vocabulary classifies them well too. They get their
// OWN Set objects: `{ ...AWS }` shared AWS's mutation/read/highRisk instances,
// so any per-CLI addition silently rewrote aws's tables as well.
export const AZ: ToolConfig = {
  names: ["az"],
  verbPosition: "any",
  mutation: new Set(AWS.mutation),
  read: new Set(AWS.read),
  // Azure's credential endpoint: `az account get-access-token` hands out a
  // bearer token, so it is high-risk, not a read.
  highRisk: new Set([...AWS.highRisk!, "get-access-token"]),
  // `az keyvault secret show` returns the material; `secret list` does not
  // (list is excluded by ENUMERATION_VERBS in classify.ts).
  secretNouns: new Set(["secret", "secrets"]),
};

export const GCLOUD: ToolConfig = {
  names: ["gcloud"],
  verbPosition: "any",
  mutation: new Set(AWS.mutation),
  read: new Set(AWS.read),
  // `gcloud auth print-access-token` / `print-identity-token` and
  // `gcloud secrets versions access` all return credentials. These are matched
  // as WHOLE verbs (see isHighRiskVerb): `access` must not swallow
  // `access-context-manager policies list`, a plain read.
  highRisk: new Set([...AWS.highRisk!, "access", "print-access-token", "print-identity-token"]),
  secretNouns: new Set(["secret", "secrets"]),
};

// ── kubectl ──────────────────────────────────────────────────────
// Verb is (almost) always the first token: `kubectl <verb> ...`. The
// exceptions are the "config" and "auth" command groups, where the real
// sub-verb is the second token (`config use-context`, `auth can-i`).
// NOTE: getContext (live current-context for confirm prompts) is composed
// on in infra-safety.ts — it's pi-wired and must not live in this pi-free file.
export const KUBECTL: ToolConfig = {
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
  // `config view --raw` prints the kubeconfig verbatim — client key material
  // included; plain `config view` renders it redacted and stays a read.
  highRiskFlags: [{ verb: "config view", flags: ["--raw"] }],
  // A Secret's data is base64, not encryption: `kubectl get secret … -o yaml`
  // reveals it. Enumeration (`get secrets`) is caught by the same rule; `get
  // pods` carries no secret noun and stays read-only.
  secretNouns: new Set(["secret", "secrets"]),
  // `kubectl describe secret` prints the DATA KEYS and their byte counts, never
  // the values, so it stays a metadata read. Only `describe` is restored: `get`
  // must keep blocking.
  secretMetadataVerbs: new Set(["describe"]),
};

// ── terraform / tofu ───────────────────────────────────────────
// Same grammar and subcommands; tofu is a drop-in OpenTofu fork.
export const TERRAFORM: ToolConfig = {
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
  // State and outputs carry attribute values verbatim, so the -json forms print
  // whatever secrets the plan/state holds. `terraform output` / `show` are
  // otherwise ordinary reads (they filter sensitive values).
  highRiskFlags: [
    { verb: "output", flags: ["-json"] },
    { verb: "show", flags: ["-json"] },
  ],
};

/** All infra tool configs, in guard-registration order. */
export const TOOLS: ToolConfig[] = [AWS, AZ, GCLOUD, KUBECTL, TERRAFORM];
