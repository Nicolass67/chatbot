/** Scroll rapide et fluide vers le bas d'un conteneur. */
export function smoothScrollToBottom(
  element: HTMLElement,
  durationMs = 280
): void {
  const target = Math.max(0, element.scrollHeight - element.clientHeight);
  const start = element.scrollTop;
  const distance = target - start;

  if (Math.abs(distance) < 2) {
    element.scrollTop = target;
    return;
  }

  const startTime = performance.now();
  const easeOutCubic = (t: number) => 1 - (1 - t) ** 3;

  const step = (now: number) => {
    const progress = Math.min((now - startTime) / durationMs, 1);
    element.scrollTop = start + distance * easeOutCubic(progress);
    if (progress < 1) {
      requestAnimationFrame(step);
    }
  };

  requestAnimationFrame(step);
}

export function isScrolledUpFromBottom(
  element: HTMLElement,
  thresholdPx = 120
): boolean {
  const distanceFromBottom =
    element.scrollHeight - element.scrollTop - element.clientHeight;
  return distanceFromBottom > thresholdPx;
}
