/** Abort both fetch and body reads. Deadlines never authorize a retry. */
export const REQUEST_MS = 15_000;
export const MESSAGE_MS = 30_000;
const MAX_BODY_BYTES = 256 * 1024;

export async function deadline<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  milliseconds: number,
  parent?: AbortSignal,
): Promise<T> {
  const controller = new AbortController();
  const abort = () => controller.abort();
  parent?.addEventListener("abort", abort, { once: true });
  if (parent?.aborted) abort();
  const timer = setTimeout(abort, milliseconds);
  let rejectAbort: () => void = () => {};
  const expired = new Promise<never>((_, reject) => {
    rejectAbort = () => reject(new Error("Operation deadline exceeded"));
    controller.signal.addEventListener("abort", rejectAbort, { once: true });
  });
  try {
    controller.signal.throwIfAborted();
    return await Promise.race([operation(controller.signal), expired]);
  } finally {
    clearTimeout(timer);
    parent?.removeEventListener("abort", abort);
    controller.signal.removeEventListener("abort", rejectAbort);
  }
}

export async function requestJSON(
  url: URL | string,
  init: RequestInit = {},
  parent?: AbortSignal,
  milliseconds = REQUEST_MS,
): Promise<{ status: number; ok: boolean; payload: unknown }> {
  return deadline(async (signal) => {
    signal.throwIfAborted();
    const response = await fetch(url, { ...init, signal });
    if (!response.ok) {
      await response.body?.cancel();
      return { status: response.status, ok: false, payload: null };
    }
    // Mutation endpoints need only their HTTP acknowledgement; still close bodies.
    if (init.method === "POST" && init.headers &&
        new Headers(init.headers).get("Content-Type") === "application/json") {
      await response.body?.cancel();
      return { status: response.status, ok: true, payload: null };
    }
    const reader = response.body?.getReader();
    let size = 0;
    const chunks: Uint8Array[] = [];
    try {
      if (reader) while (true) {
        signal.throwIfAborted();
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BODY_BYTES) throw new Error("Response too large");
        chunks.push(value);
      }
      const body = Buffer.concat(chunks);
      return { status: response.status, ok: true, payload: body.length ? JSON.parse(body.toString("utf8")) : null };
    } finally {
      await reader?.cancel().catch(() => {});
    }
  }, milliseconds, parent);
}
