import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  countPosts,
  decodeCursor,
  encodeCursor,
  fetchFeed,
  setReaction,
} from '../src/repository';
import { createTestDatabase, type TestDatabase } from './pglite';

const VIEWER = 'viewer-a';
const OTHER = 'viewer-b';
const POST = 'hogsmeade-welcome';

let harness: TestDatabase;

beforeAll(async () => {
  harness = await createTestDatabase();
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await harness.reset();
});

describe('cursor codec', () => {
  it('round trips a sequence number', () => {
    expect(decodeCursor(encodeCursor(42))).toBe(42);
  });

  it('treats absent, malformed and non positive cursors as the start of the feed', () => {
    expect(decodeCursor(undefined)).toBeNull();
    expect(decodeCursor('')).toBeNull();
    expect(decodeCursor('%%%not-base64%%%')).toBeNull();
    expect(decodeCursor(btoa('0'))).toBeNull();
    expect(decodeCursor(btoa('-5'))).toBeNull();
  });
});

describe('feed paging', () => {
  it('returns the newest posts first and reports a cursor while more remain', async () => {
    const page = await fetchFeed(harness.db, VIEWER, null, 5);

    expect(page.items).toHaveLength(5);
    expect(page.items[0].id).toBe('forbidden-section');
    expect(page.nextCursor).not.toBeNull();
  });

  it('walks every post exactly once and then reports no cursor', async () => {
    const seen: string[] = [];
    let cursor: number | null = null;

    for (let page = 0; page < 10; page += 1) {
      const result = await fetchFeed(harness.db, VIEWER, cursor, 4);
      seen.push(...result.items.map((item) => item.id));
      cursor = result.nextCursor ? decodeCursor(result.nextCursor) : null;
      if (cursor === null) break;
    }

    expect(cursor).toBeNull();
    expect(seen).toHaveLength(await countPosts(harness.db));
    expect(new Set(seen).size).toBe(seen.length);
  });

  it('returns an empty page once the cursor is past the oldest post', async () => {
    const page = await fetchFeed(harness.db, VIEWER, 1, 5);

    expect(page.items).toEqual([]);
    expect(page.nextCursor).toBeNull();
  });

  it('clamps the page size and ignores nonsense limits', async () => {
    expect((await fetchFeed(harness.db, VIEWER, null, 1000)).items.length).toBe(
      await countPosts(harness.db),
    );
    expect((await fetchFeed(harness.db, VIEWER, null, 0)).items.length).toBe(5);
    expect((await fetchFeed(harness.db, VIEWER, null, Number.NaN)).items.length).toBe(5);
  });
});

describe('reactions', () => {
  it('increments once no matter how often the like is replayed', async () => {
    const before = await countLikes(POST);

    await react('post_likes', POST, true);
    const second = await react('post_likes', POST, true);
    const third = await react('post_likes', POST, true);

    expect(second.likes).toBe(before + 1);
    expect(third.likes).toBe(before + 1);
    expect(third.isLiked).toBe(true);
  });

  it('never decrements twice when an unlike is replayed', async () => {
    await react('post_likes', POST, true);
    const afterLike = await countLikes(POST);

    await react('post_likes', POST, false);
    const second = await react('post_likes', POST, false);

    expect(second.likes).toBe(afterLike - 1);
    expect(second.isLiked).toBe(false);
  });

  it('never drives a counter below zero', async () => {
    const original = await countLikes(POST);

    const result = await react('post_likes', POST, false);

    expect(result.likes).toBe(original);
  });

  it('keeps the shared counter global while flags stay per viewer', async () => {
    await react('post_likes', POST, true);
    const before = await countLikes(POST);

    const mine = await fetchFeed(harness.db, VIEWER, null, 20);
    const theirs = await fetchFeed(harness.db, OTHER, null, 20);

    const minePost = mine.items.find((item) => item.id === POST);
    const theirPost = theirs.items.find((item) => item.id === POST);

    expect(minePost?.isLiked).toBe(true);
    expect(theirPost?.isLiked).toBe(false);
    expect(theirPost?.likes).toBe(before);
  });

  it('saves follow the same idempotent contract', async () => {
    const before = await countSaves(POST);

    await react('post_saves', POST, true);
    const repeat = await react('post_saves', POST, true);
    const removed = await react('post_saves', POST, false);
    const removedAgain = await react('post_saves', POST, false);

    expect(repeat.saves).toBe(before + 1);
    expect(removed.saves).toBe(before);
    expect(removedAgain.saves).toBe(before);
  });

  it('reports an unknown post without writing anything', async () => {
    const result = await setReaction(harness.db, 'post_likes', 'does-not-exist', VIEWER, true);
    const rows = await harness.db.query('SELECT COUNT(*)::int AS total FROM post_likes');

    expect(result).toBeNull();
    expect(rows.rows[0]).toEqual({ total: 0 });
  });
});

async function react(
  kind: 'post_likes' | 'post_saves',
  postId: string,
  enabled: boolean,
) {
  const result = await setReaction(harness.db, kind, postId, VIEWER, enabled);
  if (!result) throw new Error(`expected post ${postId} to exist`);
  return result;
}

async function countLikes(postId: string): Promise<number> {
  const result = await harness.db.query<{ total: number }>(
    'SELECT likes AS total FROM posts WHERE id = $1',
    [postId],
  );
  return result.rows[0]?.total ?? 0;
}

async function countSaves(postId: string): Promise<number> {
  const result = await harness.db.query<{ total: number }>(
    'SELECT saves AS total FROM posts WHERE id = $1',
    [postId],
  );
  return result.rows[0]?.total ?? 0;
}
