import { beforeEach, describe, expect, it } from 'vitest';
import {
  UPLOAD_RATE_LIMIT,
  UPLOAD_TOKEN_HEADER,
  guardWrite,
  resetRateLimits,
} from '../src/write-guard';

/** A stand in for the Hono context: the guard only reads the client address off it. */
const scopeFor = (address: string) => ({ request: { header: (name: string) => name === 'cf-connecting-ip' ? address : undefined } });

const NOW = 1_700_000_000_000;

let scope: object;

beforeEach(() => {
  scope = {};
});

describe('guardWrite', () => {
  it('lets a request carrying the token through', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);

    expect(verdict).toEqual({ ok: true });
  });

  it('fails closed when the secret was never configured', () => {
    const verdict = guardWrite({}, scope, undefined, NOW);

    expect(verdict).toEqual({ ok: false, status: 401, error: 'uploads_not_configured' });
  });

  it('does not treat a missing secret as an open door', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: '' }, scope, '', NOW);

    expect(verdict.ok).toBe(false);
  });

  it('rejects a missing token', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, undefined, NOW);

    expect(verdict).toEqual({ ok: false, status: 401, error: 'unauthorized' });
  });

  it('rejects the wrong token', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'guess', NOW);

    expect(verdict.ok).toBe(false);
  });

  it('rejects a correct prefix, since a partial secret is still not the secret', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret-long' }, scope, 'secret', NOW);

    expect(verdict.ok).toBe(false);
  });

  it('rejects a token with trailing characters', () => {
    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret ', NOW);

    expect(verdict.ok).toBe(false);
  });

  it('reads the token from the header the client sends', () => {
    expect(UPLOAD_TOKEN_HEADER).toBe('x-upload-token');
  });

  it('allows a burst up to the limit', () => {
    for (let attempt = 1; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW).ok).toBe(true);
    }
  });

  it('rejects the request after the limit', () => {
    for (let attempt = 0; attempt < UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);
    }

    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);

    expect(verdict).toEqual({ ok: false, status: 429, error: 'rate_limited' });
  });

  it('starts a fresh budget once the window has passed', () => {
    for (let attempt = 0; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);
    }

    const later = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW + 61_000);

    expect(later.ok).toBe(true);
  });

  it('charges an unauthenticated caller nothing, so a flood cannot lock out the real one', () => {
    for (let attempt = 0; attempt < 200; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'wrong', NOW);
    }

    const verdict = guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);

    expect(verdict.ok).toBe(true);
  });

  it('keeps separate budgets per client address', () => {
    // One app instance, so one rate log, reached by two different callers.
    const first = scopeFor('10.0.0.1');
    const second = scopeFor('10.0.0.2');

    for (let attempt = 0; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, first, 'secret', NOW);
    }

    expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, first, 'secret', NOW).ok).toBe(false);
    expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, second, 'secret', NOW).ok).toBe(true);
  });

  it('shares one budget across addresses when the runtime does not tell us who is calling', () => {
    const blind = { request: { header: () => undefined } };

    for (let attempt = 0; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, blind, 'secret', NOW);
    }

    expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, blind, 'secret', NOW).ok).toBe(false);
  });

  it('keeps budgets per app instance, since each isolate gets its own memory', () => {
    const other = {};

    for (let attempt = 0; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, other, 'secret', NOW);
    }

    expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW).ok).toBe(true);
  });

  it('can be reset, which is what tests use between cases', () => {
    for (let attempt = 0; attempt <= UPLOAD_RATE_LIMIT; attempt += 1) {
      guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW);
    }
    resetRateLimits(scope);

    expect(guardWrite({ UPLOAD_TOKEN: 'secret' }, scope, 'secret', NOW).ok).toBe(true);
  });
});