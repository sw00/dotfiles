/**
 * Regression tests for ./hypa-unwrap.ts.
 *
 * Runs standalone with no pi runtime:
 *   node --experimental-strip-types --test lib/hypa-unwrap.test.ts
 */

import { unwrapHypaC, unwrapHypaCli, unwrapHypaCommand } from "./hypa-unwrap.ts";

const KNOWN = new Set(["aws", "kubectl", "terraform"]);

const cases: Array<[string, string, string]> = [
  // hypa -c generic wrapper
  ['hypa -c "aws s3 ls"', "aws s3 ls", "unwrap double"],
  ["hypa -c 'aws s3 ls'", "aws s3 ls", "unwrap single"],
  ["hypa -c aws s3 ls", "aws s3 ls", "unwrap unquoted"],
  ['hypa -c "aws s3 ls; kubectl get pods"', "aws s3 ls; kubectl get pods", "unwrap compound"],
  ['hypa --command "aws s3 ls"', "aws s3 ls", "unwrap --command"],
  ["hypa -c \"echo $(aws s3 ls)\"", "echo $(aws s3 ls)", "unwrap substitution"],

  // hypa <cli> tool-specific wrapper
  ["hypa kubectl get pods", "kubectl get pods", "unwrap kubectl"],
  ["hypa kubectl delete pod foo", "kubectl delete pod foo", "unwrap kubectl delete"],
  ["hypa aws s3 ls", "aws s3 ls", "unwrap aws"],
  ["hypa terraform plan", "terraform plan", "unwrap terraform"],

  // passthrough: unchanged when not a known wrapper
  ["aws s3 ls", "aws s3 ls", "no hypa prefix"],
  ["hypa -c ls", "ls", "hypa -c ls"],
  ["hypa ls -la", "hypa ls -la", "hypa ls unknown cli"],
  ["hypa rewrite --json aws s3 ls", "hypa rewrite --json aws s3 ls", "hypa rewrite not a cli wrapper"],
  ["hypa mcp list", "hypa mcp list", "hypa mcp not a cli wrapper"],
];

let pass = 0;
let fail = 0;
for (const [cmd, expected, label] of cases) {
  const got = unwrapHypaCommand(cmd, KNOWN);
  const ok = got === expected;
  console.log(`${ok ? "✓" : "✗"}  ${label.padEnd(35)} | ${got === null ? "(null)" : got} | ${cmd}`);
  ok ? pass++ : fail++;
}

// unwrapHypaC / unwrapHypaCli direct tests
const cOnly = unwrapHypaC("hypa -c 'aws s3 ls'");
console.log(`${cOnly === "aws s3 ls" ? "✓" : "✗"}  unwrapHypaC direct`);
cOnly === "aws s3 ls" ? pass++ : fail++;

const cliOnly = unwrapHypaCli("hypa kubectl get pods", KNOWN);
console.log(`${cliOnly === "kubectl get pods" ? "✓" : "✗"}  unwrapHypaCli direct`);
cliOnly === "kubectl get pods" ? pass++ : fail++;

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
