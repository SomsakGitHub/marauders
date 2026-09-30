/**
 * Gate for the two endpoints that write to the bucket and the database.
 *
 * Neither endpoint is otherwise protected: the Worker URL is all anyone needs to store 64MB
 * objects in R2 and put rows in Neon. A shared token is not user auth and is not a substitute
 * for it, but it closes the door on drive-by abuse from someone who merely knows the URL, which
 * is the realistic threat while the app has no accounts.
 */

/** Required on write endpoints. Set as a Worker secret, never in wrangler.toml. */
export const UPLOAD_TOKEN_HEADER = 'x-upload-token';

/** Uploads allowed per client per window. */
export const UPLOAD_RATE_LIMIT = 20;

/** Length of the rate limit window, in seconds. */
export const UPLOAD_RATE_WINDOW_SECONDS = 60;

/** Per-isolate request log. Workers do not share memory, so this is a floor and not a cap. */
type RateLog = Map<string, { count: number; resetAt: number }>;

const rateLogs = new WeakMap<object, RateLog>();

function logFor(scope: object): RateLog {
  const existing = rateLogs.get(scope);
  if (existing) return existing;
  const created: RateLog = new Map();
  rateLogs.set(scope, created);
  return created;
}

export type WriteGuardResult =
  | { ok: true }
  | { ok: false; status: 401 | 429; error: string };

/**
 * Checks the token, then charges the rate limit.
 *
 * The token is compared over the whole string so a prefix does not pass, and the comparison does
 * not short circuit, so the time taken does not leak how many characters were right.
 */
export function guardWrite(
  bindings: Record<string, unknown>,
  scope: object,
  supplied: string | undefined,
  now: number,
): WriteGuardResult {
  const expected = typeof bindings.UPLOAD_TOKEN === 'string' ? bindings.UPLOAD_TOKEN : '';

  // A Worker without the secret configured fails closed rather than accepting every write.
  if (expected.length === 0) {
    return { ok: false, status: 401, error: 'uploads_not_configured' };
  }

  if (!matches(supplied ?? '', expected)) {
    return { ok: false, status: 401, error: 'unauthorized' };
  }

  const key = rateKeyFor(scope);
  const log = logFor(scope);
  const windowEnd = now + UPLOAD_RATE_WINDOW_SECONDS * 1000;

  // The key is the client address when the runtime provides one, which is the only thing that
  // distinguishes callers here since they all share the token.
  const entry = log.get(key);
  if (!entry || entry.resetAt <= now) {
    log.set(key, { count: 1, resetAt: windowEnd });
    return { ok: true };
  }

  if (entry.count >= UPLOAD_RATE_LIMIT) {
    return { ok: false, status: 429, error: 'rate_limited' };
  }

  entry.count += 1;
  return { ok: true };
}

/** Clears the rate log. Tests only. */
export function resetRateLimits(scope: object): void {
  rateLogs.delete(scope);
}

function rateKeyFor(scope: object): string {
  const address = (scope as { request?: { header?: (name: string) => string | undefined } })
    .request?.header?.('cf-connecting-ip');
  return address?.trim() || 'unknown';
}

/** Length independent, non short circuiting comparison. */
function matches(supplied: string, expected: string): boolean {
  if (supplied.length !== expected.length) return false;

  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= supplied.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
}