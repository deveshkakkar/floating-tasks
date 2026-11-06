import { fetchArchivedTasks } from "./archive.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export async function restoreArchivedTask(target: string): Promise<string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken();
  if (!accessToken) return LOGIN_REQUIRED;

  const result = await fetchArchivedTasks();
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
    const response = await fetch(endpoint, {
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ externalId: task.externalId }),
    });
    if (!response.ok) return `Restore failed with status ${response.status}.`;
    return `Restored: ${task.text}`;
  } catch {
    return "Restore could not reach the task service.";
  }
}
