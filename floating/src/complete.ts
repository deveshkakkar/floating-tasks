import { requestJSON } from "./request.ts";
import { fetchActiveTasks } from "./query.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export async function completeTask(target: string, signal?: AbortSignal): Promise<string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken(signal);
  if (!accessToken) return LOGIN_REQUIRED;

  const result = await fetchActiveTasks(signal);
  if (typeof result === "string") return result;
  const normalizedTarget = target.trim().toLowerCase();
  const task = result.find((item) =>
    item.externalId.toLowerCase() === normalizedTarget || item.text.trim().toLowerCase() === normalizedTarget,
  );
  if (!task) {
    return "I could not find that active task. Use `query` to see its ID or exact text.";
  }

  try {
    const endpoint = new URL("v1/reminders/complete", `${apiURL.replace(/\/$/, "")}/`);
    const response = await requestJSON(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ externalId: task.externalId }),
    }, signal);
    if (response.status === 409) return "Complete Apple Reminders tasks in the Reminders app first.";
    if (!response.ok || response.status === 202) return `Completion is not confirmed (status ${response.status}). Query tasks before trying again.`;
    return `Completed: ${task.text}`;
  } catch {
    return "Completion could not be confirmed. It may have completed; query tasks before trying again.";
  }
}
