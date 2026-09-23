import { requestJSON } from "./request.ts";
import { fetchArchivedTasks } from "./archive.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export async function restoreArchivedTask(target: string, signal?: AbortSignal): Promise<string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken(signal);
  if (!accessToken) return LOGIN_REQUIRED;

  const result = await fetchArchivedTasks(signal);
  if (typeof result === "string") return result;
  const normalizedTarget = target.trim().toLowerCase();
  const task = result.find((item) =>
    item.externalId.toLowerCase() === normalizedTarget || item.text.trim().toLowerCase() === normalizedTarget,
  );
  if (!task) {
    return "I could not find that archived task. Use `archived` to see its ID or exact text.";
  }

  try {
    const endpoint = new URL("v1/reminders/restore", `${apiURL.replace(/\/$/, "")}/`);
    const response = await requestJSON(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ externalId: task.externalId }),
    }, signal);
    if (!response.ok || response.status === 202) return `Restore is not confirmed (status ${response.status}). Check archived and active tasks before trying again.`;
    return `Restored: ${task.text}`;
  } catch {
    return "Restore could not be confirmed. It may have completed; check archived and active tasks before trying again.";
  }
}
