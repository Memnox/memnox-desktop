/** Seconds in a minute, for the stopwatch. */
const SECONDS_PER_MINUTE = 60;

/** Minutes and seconds, the way a stopwatch shows how long an answer has taken: `0:07`. Ported from `clock(_:)`. */
export function clock(ms: number): string {
  const whole = Math.max(0, Math.floor(ms / 1_000));
  return `${Math.floor(whole / SECONDS_PER_MINUTE)}:${String(whole % SECONDS_PER_MINUTE).padStart(2, '0')}`;
}
