/**
 * Settle Notify Extension
 *
 * Two surfaces, one signal — "this workstream wants a human":
 *
 *   1. a desktop notification, for when you are looking somewhere else entirely;
 *   2. a tmux window flag (`@pi_waiting`), for when you are in tmux but in another
 *      window. `tmux.conf` renders it as `!` in the window list and clears it when the
 *      window is looked at, so it reads as an inbox rather than a log.
 *
 * `agent_settled`, never `agent_end`: pi may auto-retry, auto-compact and retry, or pick
 * up queued messages after `agent_end`, so notifying there fires mid-task. An ABORTED run
 * is skipped — Escape means the human is already looking. `agent_start` clears the flag
 * (the work resumed), and `ui_prompt_start` covers a blocking confirm/select, which is a
 * directly-reported "blocked" rather than one inferred from output.
 *
 * Fail-safe by construction: both surfaces are cosmetic, so every path swallows its error
 * instead of surfacing an extension failure into the session. pi defers work requested
 * from these handlers until all settled handlers finish, so dispatch cannot re-enter.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Silences the PUSH only: the window flag is silent already, so it stays on. */
const MUTE = process.env.PI_SETTLE_NOTIFY === "0";
/** Test seam: replaces the transport entirely, so the suite never fires a real toast. */
const TEST_CMD = process.env.SETTLE_NOTIFY_CMD;

/** `tmux set-window-option` names this pane's window; a no-op outside tmux. */
const FLAG = "@pi_waiting";

/**
 * Free text reaches PowerShell as UTF-8 base64, decoded there: base64 has no quote
 * characters, and PowerShell also treats `’`/`‘` as single quotes, so a branch name
 * could otherwise close the literal and run commands on the Windows host.
 */
function psText(s: string): string {
  return `[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${Buffer.from(s, "utf8").toString("base64")}'))`;
}

/** Zero-dep WinRT toast; no wslu, no wsl-notify-send. `'pi'` is the app id shown. */
function wslToast(title: string, body: string): string {
  return [
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null",
    "$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)",
    "$t = $x.GetElementsByTagName('text')",
    `$t.Item(0).AppendChild($x.CreateTextNode(${psText(title)})) > $null`,
    `$t.Item(1).AppendChild($x.CreateTextNode(${psText(body)})) > $null`,
    "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('pi').Show([Windows.UI.Notifications.ToastNotification]::new($x))",
  ].join("\n");
}

/**
 * On the WSL path the text is base64 inside the script, so no character of it can close a
 * literal or start a statement; every other transport passes it as ARGV.
 */
async function notify(pi: ExtensionAPI, title: string, body: string): Promise<void> {
  try {
    if (TEST_CMD) {
      await pi.exec(TEST_CMD, [title, body], { timeout: 5000 });
    } else if (process.platform === "darwin") {
      await pi.exec(
        "osascript",
        ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run", title, body],
        { timeout: 5000 },
      );
    } else if (process.env.WSL_DISTRO_NAME) {
      await pi.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", wslToast(title, body)], { timeout: 8000 });
    } else {
      await pi.exec("notify-send", ["--", title, body], { timeout: 5000 });
    }
  } catch {
    // Cosmetic. Silence, not a session error.
  }
}

/** Raise or clear the window flag; outside tmux there is no window to mark. */
async function flag(pi: ExtensionAPI, on: boolean): Promise<void> {
  const pane = process.env.TMUX_PANE;
  if (!process.env.TMUX || !pane) return;
  const args = on
    ? ["set-window-option", "-t", pane, FLAG, "1"]
    : ["set-window-option", "-u", "-t", pane, FLAG];
  try {
    await pi.exec("tmux", args, { timeout: 4000 });
  } catch {
    // Cosmetic.
  }
}

/** `repo/branch`, so a push is actionable; falls back to the directory name. */
async function label(pi: ExtensionAPI, cwd: string): Promise<string> {
  try {
    const r = await pi.exec("git", ["rev-parse", "--abbrev-ref", "HEAD", "--show-toplevel"], { cwd, timeout: 4000 });
    const [branch, top] = String(r.stdout ?? "").trim().split("\n");
    if (branch && top) return `${top.split("/").pop()}/${branch}`;
  } catch {
    // Not a repo, or no git: the cwd is a fine label.
  }
  return cwd.split("/").pop() || cwd;
}

/** True when this pane is one the attached client is actually looking at. */
async function focused(pi: ExtensionAPI): Promise<boolean> {
  const pane = process.env.TMUX_PANE;
  if (!process.env.TMUX || !pane) return false;
  try {
    const r = await pi.exec("tmux", ["display-message", "-p", "-t", pane, "#{pane_active}#{window_active}"], { timeout: 4000 });
    return String(r.stdout ?? "").trim() === "11";
  } catch {
    return false;
  }
}

export default function settleNotify(pi: ExtensionAPI): void {
  const fire = async (cwd: string, what: string): Promise<void> => {
    await flag(pi, true);
    if (MUTE) return; // the bar stays honest; only the popup is muted
    if (await focused(pi)) return;
    await notify(pi, await label(pi, cwd), what);
  };

  pi.on("agent_start", async () => {
    await flag(pi, false);
  });

  pi.on("agent_settled", async (event, ctx) => {
    if (event.aborted) return;
    await fire(ctx.cwd, "settled — waiting on you");
  });

  pi.on("ui_prompt_start", async (_event, ctx) => {
    await fire(ctx.cwd, "needs an answer");
  });
}
