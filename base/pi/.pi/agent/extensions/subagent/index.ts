// Loads pi's subagent extension from the ACTIVE release instead of vendoring a copy.
//
// pi ships this extension as an example inside its own package and maintains it
// there (`<release>/node_modules/@earendil-works/pi-coding-agent/examples/
// extensions/subagent/`), so a vendored copy drifts out of date silently and
// needs a manual re-vendor + re-stamp on every pi upgrade.  Resolving the
// installed release at load time keeps this file version-matched by
// construction, which is what the pin-and-compare ritual was approximating.
//
// Why not a package or a pinned path: `pi install` discovers extensions only
// through a package manifest or a conventional `extensions/` dir, and the
// example has neither; a path pinned to `releases/<version>/…` is deleted by
// pi's own release pruning on the next self-update (it keeps only the active and
// running releases), so it would dangle silently.  Details, and what breaks if
// pi changes its layout, are in docs/GOTCHAS.md under "pi".
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Factory = (pi: ExtensionAPI) => void;

const INSTALL_ROOT = join(homedir(), ".pi/agent/install");
const EXAMPLE_REL =
	"node_modules/@earendil-works/pi-coding-agent/examples/extensions/subagent/index.ts";

async function loadExample(): Promise<Factory> {
	const versionPath = join(INSTALL_ROOT, "current-version");
	let target = versionPath;
	try {
		const version = readFileSync(versionPath, "utf8").trim();
		target = join(INSTALL_ROOT, "releases", version, EXAMPLE_REL);
		const mod = (await import(target)) as { default?: unknown };
		if (typeof mod.default !== "function") {
			throw new Error("its default export is not an extension factory");
		}
		return mod.default as Factory;
	} catch (error) {
		// Loud on purpose: this file depends on pi's release layout being stable
		// across versions, and a change there must surface at load, naming the
		// path it tried.
		throw new Error(
			`subagent: cannot load pi's subagent example from ${target} — pi's release layout changed?` +
				` (${error instanceof Error ? error.message : String(error)})`,
		);
	}
}

export default await loadExample();
