import { requestJSON } from "./request.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

export type ArchivedTask = { externalId: string; text: string };

type ArchivedTaskResponse = {
  items?: ArchivedTask[];
};

export async function fetchArchivedTasks(signal?: AbortSignal): Promise<ArchivedTask[] | string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken(signal);

  if (!accessToken) return LOGIN_REQUIRED;

  try {
    const endpoint = new URL("v1/reminders/archived", `${apiURL.replace(/\/$/, "")}/`);
    const response = await requestJSON(endpoint, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }, signal);

    if (!response.ok) {
      return `Archive lookup failed with status ${response.status}.`;
    }

    const payload = response.payload as ArchivedTaskResponse;
    return payload.items ?? [];
  } catch {
    return "Archive lookup could not reach the task service.";
  }
}

export async function queryArchivedTasks(signal?: AbortSignal): Promise<string> {
  const result = await fetchArchivedTasks(signal);
  if (typeof result === "string") return result;
  const tasks = result;
  if (tasks.length === 0) {
    return "You have no archived tasks.";
  }

  return ["Archived tasks:", ...tasks.map((task, index) => `${index + 1}. ${task.text} [${task.externalId}]`)].join("\n");
}
