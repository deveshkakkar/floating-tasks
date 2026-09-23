import { requestJSON } from "./request.ts";
import { getAccessToken, LOGIN_REQUIRED } from "./auth.ts";
import { API_URL } from "./config.ts";

type DailyTask = { text: string };

type DailyTaskResponse = {
  items?: DailyTask[];
};

export async function queryDailyTasks(signal?: AbortSignal): Promise<string> {
  const apiURL = API_URL;
  const accessToken = await getAccessToken(signal);

  if (!accessToken) return LOGIN_REQUIRED;

  try {
    const endpoint = new URL("v1/reminders/daily", `${apiURL.replace(/\/$/, "")}/`);
    const response = await requestJSON(endpoint, {
      headers: { Authorization: `Bearer ${accessToken}` },
    }, signal);
    if (!response.ok) return `Daily lookup failed with status ${response.status}.`;

    const payload = response.payload as DailyTaskResponse;
    const tasks = payload.items ?? [];
    if (tasks.length === 0) return "There are no daily tasks selected yet.";
    return ["Today’s tasks:", ...tasks.map((task, index) => `${index + 1}. ${task.text}`)].join("\n");
  } catch {
    return "Daily lookup could not reach the task service.";
  }
}
