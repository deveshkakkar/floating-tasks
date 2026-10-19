// Typing is best effort. A stalled provider call must not hold the request slot.
export type TypingSpace = {
  startTyping?: () => Promise<void>;
  stopTyping?: () => Promise<void>;
};

async function bounded(promise: Promise<unknown>, ms: number): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([promise.catch(() => {}), new Promise<void>(resolve => {
      timer = setTimeout(resolve, ms);
    })]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function withTyping<T>(space: TypingSpace, work: () => Promise<T>,
  refreshMs = 5000, providerTimeoutMs = 1000): Promise<T> {
  if (!space.startTyping || !space.stopTyping) return work();
  let active = true;
  let stopIssued = false;
  let pending: Promise<void> | undefined;
  const stop = () => Promise.resolve().then(() => space.stopTyping!()).catch(() => {});
  const pulse = () => {
    if (!active || pending) return;
    const started = Promise.resolve().then(() => space.startTyping!()).catch(() => {});
    pending = started.then(() => {
      pending = undefined;
      // A slow start may finish after cleanup; clear that late signal too.
      if (!active && stopIssued) void stop();
    });
  };
  pulse();
  const timer = setInterval(pulse, refreshMs);
  timer.unref();
  try {
    return await work();
  } finally {
    active = false;
    clearInterval(timer);
    if (pending) await bounded(pending, providerTimeoutMs);
    stopIssued = true;
    await bounded(stop(), providerTimeoutMs);
  }
}
