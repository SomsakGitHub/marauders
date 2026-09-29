import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/index';
import type { FeedPage, PostPayload, ReactionResult } from '../src/types';
import { createTestDatabase, type TestDatabase } from './pglite';

const POST = 'hogsmeade-welcome';
const ENV = { DATABASE_URL: 'postgres://unused/test' };

let harness: TestDatabase;
let app: ReturnType<typeof createApp>;

beforeAll(async () => {
  harness = await createTestDatabase();
  app = createApp(() => harness.db);
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await harness.reset();
});

const getFeed = async (query = '', viewer?: string) => {
  const response = await app.request(
    `http://local/api/feed${query}`,
    viewer ? { headers: { 'x-viewer-id': viewer } } : undefined,
    ENV,
  );
  return { status: response.status, body: (await response.json()) as FeedPage };
};

const react = async (postId: string, action: 'like' | 'save', method: string, viewer?: string) => {
  const response = await app.request(
    `http://local/api/posts/${postId}/${action}`,
    {
      method,
      headers: viewer ? { 'x-viewer-id': viewer } : undefined,
    },
    ENV,
  );
  return { status: response.status, body: (await response.json()) as ReactionResult };
};

describe('GET /api/health', () => {
  it('reports the row count', async () => {
    const response = await app.request('http://local/api/health', undefined, ENV);
    const body = (await response.json()) as { status: string; posts: number };

    expect(response.status).toBe(200);
    expect(body.status).toBe('ok');
    expect(body.posts).toBe(14);
  });
});

describe('GET /api/feed', () => {
  it('serves the newest posts first', async () => {
    const { status, body } = await getFeed();

    expect(status).toBe(200);
    expect(body.items).toHaveLength(5);
    expect(body.items[0].id).toBe('forbidden-section');
    expect(body.nextCursor).toBeTruthy();
  });

  it('returns the camelCase shape the iOS client decodes', async () => {
    const { body } = await getFeed();
    const post = body.items[0] as PostPayload & Record<string, unknown>;

    expect(Object.keys(post).sort()).toEqual(
      [
        'author',
        'caption',
        'comments',
        'id',
        'isLiked',
        'isSaved',
        'likes',
        'music',
        'saves',
        'shares',
        'videoUrl',
      ].sort(),
    );
    expect(Object.keys(post.author).sort()).toEqual(
      ['displayName', 'emoji', 'handle', 'id', 'isVerified'].sort(),
    );
  });

  it('pages forward without repeating a post', async () => {
    const first = await getFeed('?limit=4');
    const second = await getFeed(`?limit=4&cursor=${encodeURIComponent(first.body.nextCursor ?? '')}`);

    const firstIds = first.body.items.map((item) => item.id);
    const secondIds = second.body.items.map((item) => item.id);

    expect(secondIds).toHaveLength(4);
    expect(secondIds.some((id) => firstIds.includes(id))).toBe(false);
  });

  it('falls back to the start of the feed for a malformed cursor', async () => {
    const { status, body } = await getFeed('?cursor=not-a-cursor');

    expect(status).toBe(200);
    expect(body.items[0].id).toBe('forbidden-section');
  });

  it('ignores an absurd limit', async () => {
    const { body } = await getFeed('?limit=100000');

    expect(body.items).toHaveLength(14);
    expect(body.nextCursor).toBeNull();
  });

  it('isolates the liked and saved flags per viewer', async () => {
    await react(POST, 'like', 'POST', 'viewer-a');

    const mine = await getFeed('?limit=20', 'viewer-a');
    const theirs = await getFeed('?limit=20', 'viewer-b');

    expect(mine.body.items.find((item) => item.id === POST)?.isLiked).toBe(true);
    expect(theirs.body.items.find((item) => item.id === POST)?.isLiked).toBe(false);
  });
});

describe('reactions', () => {
  it('likes a post and stays idempotent on replay', async () => {
    const first = await react(POST, 'like', 'POST');
    const replay = await react(POST, 'like', 'POST');

    expect(first.status).toBe(200);
    expect(first.body.isLiked).toBe(true);
    expect(replay.body.likes).toBe(first.body.likes);
  });

  it('unlikes a post exactly once', async () => {
    const liked = await react(POST, 'like', 'POST');
    const removed = await react(POST, 'like', 'DELETE');
    const replay = await react(POST, 'like', 'DELETE');

    expect(removed.body.likes).toBe(liked.body.likes - 1);
    expect(removed.body.isLiked).toBe(false);
    expect(replay.body.likes).toBe(removed.body.likes);
  });

  it('saves a post exactly once', async () => {
    const saved = await react(POST, 'save', 'POST');
    const replay = await react(POST, 'save', 'POST');
    const removed = await react(POST, 'save', 'DELETE');

    expect(saved.body.isSaved).toBe(true);
    expect(replay.body.saves).toBe(saved.body.saves);
    expect(removed.body.isSaved).toBe(false);
  });

  it('404s for an unknown post', async () => {
    const { status, body } = await react('nope', 'like', 'POST');

    expect(status).toBe(404);
    expect(body).toEqual({ error: 'post_not_found' } as never);
  });

  it('404s an unknown route', async () => {
    const response = await app.request('http://local/api/nothing', undefined, ENV);

    expect(response.status).toBe(404);
  });
});

describe('missing configuration', () => {
  it('503s rather than throwing when DATABASE_URL is absent', async () => {
    const bare = createApp(() => {
      throw new Error('must not be called');
    });

    const health = await bare.request('http://local/api/health', undefined, {} as never);
    const feed = await bare.request('http://local/api/feed', undefined, {} as never);

    expect(health.status).toBe(503);
    expect(feed.status).toBe(503);
  });
});
