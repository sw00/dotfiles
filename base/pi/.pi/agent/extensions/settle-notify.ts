/**
 * Settle Notify Extension
 *
 * A desktop notification when pi stops for good, or blocks on a question: the "wants a
 * human" signal, for when you are looking at something else entirely.
 *
 * `agent_settled`, never `agent_end`: pi may auto-retry, auto-compact and retry, or pick
 * up queued messages after `agent_end`, so notifying there fires mid-task. An ABORTED run
 * is skipped — Escape means the human is already looking. `ui_prompt_start` covers a
 * blocking confirm/select, which is a directly-reported "blocked" signal rather than one
 * inferred from output.
 *
 * Fail-safe by construction: a notification is cosmetic, so every path swallows its error
 * rather than surfacing an extension failure into the session. pi defers work requested
 * from these handlers until all settled handlers finish, so dispatch cannot re-enter.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MUTE = process.env.PI_SETTLE_NOTIFY === "0";
/** Test seam: replaces the transport entirely, so the suite never fires a real toast. */
const TEST_CMD = process.env.SETTLE_NOTIFY_CMD;

/** A PowerShell single-quoted literal: `'` doubles, and nothing else is interpretable. */
function psQuote(s: string): string {
  return `'${s.replace(/'/g, "''")}'`;
}

/** Zero-dep WinRT toast; no wslu, no wsl-notify-send. `'pi'` is the app id shown. */
function wslToast(title: string, body: string): string {
  return [
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null",
    "$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)",
    "$t = $x.GetElementsByTagName('text')",
    `$t.Item(0).AppendChild($x.CreateTextNode(${psQuote(title)})) > $null`,
    `$t.Item(1).AppendChild($x.CreateTextNode(${psQuote(body)})) > $null`,
    "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('pi').Show([Windows.UI.Notifications.ToastNotification]::new($x))",
  ].join("\n");
}

/** Every transport takes the text as ARGV, never as script source. */
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
  if (!process.env.TMUX || !process.env.TMUX_PANE) return false;
  try {
    const r = await pi.exec("tmux", ["display-message", "-p", "-t", process.env.TMUX_PANE, "#{pane_active}#{window_active}"], {
      timeout: 4000,
    });
    return String(r.stdout ?? "").trim() === "11";
  } catch {
    return false;
  }
}

export default function settleNotify(pi: ExtensionAPI): void {
  if (MUTE) return;

  const fire = async (cwd: string, what: string): Promise<void> => {
    if (await focused(pi)) return;
    await notify(pi, await label(pi, cwd), what);
  };

  pi.on("agent_settled", async (event, ctx) => {
    if (event.aborted) return;
    await fire(ctx.cwd, "settled — waiting on you");
  });

  pi.on("ui_prompt_start", async (_event, ctx) => {
    await fire(ctx.cwd, "needs an answer");
  });
}
