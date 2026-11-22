// Loads pi's subagent extension from the ACTIVE release instead of vendoring a copy.
//
// pi ships this extension as an example inside its own package and maintains it
// there (`<release>/node_modules/@earendil-works/pi-coding-agent/examples/
// extensions/subagent/`), so a vendored copy drifts out of date silently and
// needs a manual re-vendor + re-stamp on every pi upgrade.  Resolving the
// installed release at load time keeps this file version-matched by
// construction, which is what the pin-and-compare ritual was approximating.
//
// Why a version file at all: neither the ExtensionAPI nor the environment names
// the release that is running (the launcher exports only PI_MANAGED_INSTALL_ROOT,
// the install root). So the release directory is taken from the running script's
// own path when that points into `install/releases/<version>/` (upstream pi, incl.
// the `pi update`-while-running case), falling back to the managed install's
// `current-version`. A compiled variant (pi-bolt) has no such path, so it falls
// back — it may then load a newer example than it was built from; that is kept
// deliberately, because both sides are pi's own released code and vendoring a
// copy drifts worse (see the header above).
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
		const running = /[\\/]install[\\/]releases[\\/]([^\\/]+)[\\/]/.exec(process.argv[1] ?? "")?.[1];
		const version = running ?? readFileSync(versionPath, "utf8").trim();
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
