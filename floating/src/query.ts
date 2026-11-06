import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export type ActiveTask = { externalId: string; text: string };

type ActiveTaskResponse = {
  items?: ActiveTask[];
};

export async function fetchActiveTasks(): Promise<ActiveTask[] | string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken();

  if (!accessToken) return LOGIN_REQUIRED;

  try {
    const endpoint = new URL("v1/reminders/active", `${apiURL.replace(/\/$/, "")}/`);
    endpoint.searchParams.set("limit", "25");
    const response = await fetch(endpoint, {
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!response.ok) {
      return `Query failed with status ${response.status}.`;
    }

    const payload = (await response.json()) as ActiveTaskResponse;
    const tasks = payload.items ?? [];
    if (tasks.length === 0) {
      return "You have no active tasks.";
    }

    return tasks;
  } catch {
    return "Query could not reach the task service.";
  }
}

export async function queryActiveTasks(): Promise<string> {
  const result = await fetchActiveTasks();
  if (typeof result === "string") return result;
  if (result.length === 0) return "You have no active tasks.";
  return ["Active tasks:", ...result.map((task, index) => `${index + 1}. ${task.text} [${task.externalId}]`)].join("\n");
}
