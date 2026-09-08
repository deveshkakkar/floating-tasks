export type MessageIntent =
  | { kind: "create"; text: string }
  | { kind: "query"; text: string }
  | { kind: "daily"; text: string }
  | { kind: "archived"; text: string }
  | { kind: "restore"; target: string }
  | { kind: "complete"; target: string }
  | { kind: "help"; text: string }
  | { kind: "unknown"; text: string };

const CREATE_PREFIX = /^(?:create|add)\s+/i;
const QUERY_PREFIX = /^(?:query|fetch|show|list)\b/i;
const DAILY_PREFIX = /^(?:today|daily|what should i do)\b/i;
const ARCHIVED_QUERY = /^(?:query|fetch|show|list)\s+(?:the\s+)?archived\b/i;
const ARCHIVED_PREFIX = /^(?:archived|archive|history)\b/i;
const RESTORE_PREFIX = /^(?:restore|bring back)\s+(.+)$/i;
const COMPLETE_PREFIX = /^(?:complete|finish|done|mark done)\s+(.+)$/i;
const HELP_PREFIX = /^(?:help|commands|what can you do)\b/i;

export function classifyMessage(input: string): MessageIntent {
  const text = input.trim();
  const match = text.match(CREATE_PREFIX);

  if (!match) {
    const restoreMatch = text.match(RESTORE_PREFIX);
    if (restoreMatch?.[1]) {
      return { kind: "restore", target: restoreMatch[1].trim() };
    }
    const completeMatch = text.match(COMPLETE_PREFIX);
    if (completeMatch?.[1]) {
      return { kind: "complete", target: completeMatch[1].trim() };
    }
    if (ARCHIVED_QUERY.test(text) || ARCHIVED_PREFIX.test(text)) {
      return { kind: "archived", text };
    }
    if (DAILY_PREFIX.test(text)) {
      return { kind: "daily", text };
    }
    if (QUERY_PREFIX.test(text)) {
      return { kind: "query", text };
    }
    if (HELP_PREFIX.test(text)) {
      return { kind: "help", text };
    }
    return { kind: "unknown", text };
  }

  const taskText = text
    .slice(match[0].length)
    .replace(/^(?:a|an|the)\s+/i, "")
    .replace(/^(?:task|reminder|item)\s+/i, "")
    .replace(/^(?:to|for)\s+/i, "")
    .trim();

  return taskText
    ? { kind: "create", text: taskText }
    : { kind: "unknown", text };
}
