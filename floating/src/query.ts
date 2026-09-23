import { requestJSON } from "./request.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export type ActiveTask = { externalId: string; text: string };

type ActiveTaskResponse = {
  items?: ActiveTask[];
};

export async function fetchActiveTasks(signal?: AbortSignal): Promise<ActiveTask[] | string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken(signal);

  if (!accessToken) return LOGIN_REQUIRED;

  try {
    const endpoint = new URL("v1/reminders/active", `${apiURL.replace(/\/$/, "")}/`);
    endpoint.searchParams.set("limit", "25");
    const response = await requestJSON(endpoint, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }, signal);

    if (!response.ok) {
      return `Query failed with status ${response.status}.`;
    }

    const payload = response.payload as ActiveTaskResponse;
    const tasks = payload.items ?? [];
    if (tasks.length === 0) {
      return "You have no active tasks.";
    }

    return tasks;
  } catch {
    return "Query could not reach the task service.";
  }
}

export async function queryActiveTasks(signal?: AbortSignal): Promise<string> {
  const result = await fetchActiveTasks(signal);
  if (typeof result === "string") return result;
  if (result.length === 0) return "You have no active tasks.";
  return ["Active tasks:", ...result.map((task, index) => `${index + 1}. ${task.text} [${task.externalId}]`)].join("\n");
}
