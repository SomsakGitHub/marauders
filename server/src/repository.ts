import type {
  CreatePostInput,
  FeedPage,
  PostPayload,
  PostRow,
  ReactionResult,
  SqlClient,
} from './types';
import { DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE } from './types';

const POST_COLUMNS = `
  p.seq,
  p.id,
  p.video_url,
  p.author_id,
  p.author_handle,
  p.author_display_name,
  p.author_emoji,
  p.author_is_verified,
  p.caption,
  p.music,
  p.likes,
  p.comments_count,
  p.saves,
  p.shares,
  EXISTS (SELECT 1 FROM post_likes l WHERE l.post_id = p.id AND l.viewer_id = $1) AS is_liked,
  EXISTS (SELECT 1 FROM post_saves s WHERE s.post_id = p.id AND s.viewer_id = $1) AS is_saved
`;

export function encodeCursor(seq: number): string {
  return btoa(String(seq));
}

export function decodeCursor(cursor: string | undefined): number | null {
  if (!cursor) return null;
  try {
    const seq = Number(atob(cursor));
    return Number.isInteger(seq) && seq > 0 ? seq : null;
  } catch {
    return null;
  }
}

export function toPayload(row: PostRow): PostPayload {
  return {
    id: row.id,
    videoUrl: row.video_url,
    author: {
      id: row.author_id,
      handle: row.author_handle,
      displayName: row.author_display_name,
      emoji: row.author_emoji,
      isVerified: row.author_is_verified,
    },
    caption: row.caption,
    music: row.music,
    likes: row.likes,
    comments: row.comments_count,
    saves: row.saves,
    shares: row.shares,
    isLiked: row.is_liked,
    isSaved: row.is_saved,
  };
}

export function normalizePageSize(limit: number): number {
  if (!Number.isInteger(limit) || limit < 1) return DEFAULT_PAGE_SIZE;
  return Math.min(limit, MAX_PAGE_SIZE);
}

export async function fetchFeed(
  db: SqlClient,
  viewerId: string,
  cursor: number | null,
  limit: number,
): Promise<FeedPage> {
  const size = normalizePageSize(limit);
  const params: unknown[] = [viewerId];
  let text = `SELECT ${POST_COLUMNS} FROM posts p WHERE TRUE`;

  if (cursor !== null) {
    params.push(cursor);
    text += ` AND p.seq < $${params.length}`;
  }
  params.push(size);
  text += ` ORDER BY p.seq DESC LIMIT $${params.length}`;

  const result = await db.query<PostRow>(text, params);
  const items = result.rows.map(toPayload);
  const last = result.rows.at(-1);

  return {
    items,
    nextCursor: items.length === size && last ? encodeCursor(last.seq) : null,
  };
}

type ReactionKind = 'post_likes' | 'post_saves';

const setReactionStatement = (kind: ReactionKind, enabled: boolean): string => {
  const column = kind === 'post_likes' ? 'likes' : 'saves';

  const write = enabled
    ? `INSERT INTO ${kind} (viewer_id, post_id)
       SELECT $1, id FROM target
       ON CONFLICT DO NOTHING
       RETURNING 1`
    : `DELETE FROM ${kind}
       WHERE viewer_id = $1 AND post_id IN (SELECT id FROM target)
       RETURNING 1`;

  const adjust = enabled
    ? `SET ${column} = ${column} + 1
       WHERE id IN (SELECT id FROM target) AND EXISTS (SELECT 1 FROM written)`
    : `SET ${column} = GREATEST(${column} - 1, 0)
       WHERE id IN (SELECT id FROM target) AND EXISTS (SELECT 1 FROM written)`;

  return `
    WITH target AS (SELECT id FROM posts WHERE id = $2),
         written AS (${write})
    UPDATE posts
    ${adjust}
    RETURNING id
  `;
};

export async function setReaction(
  db: SqlClient,
  kind: ReactionKind,
  postId: string,
  viewerId: string,
  enabled: boolean,
): Promise<ReactionResult | null> {
  const [, read] = await db.transaction<PostRow>([
    { text: setReactionStatement(kind, enabled), params: [viewerId, postId] },
    {
      text: `SELECT ${POST_COLUMNS} FROM posts p WHERE p.id = $2`,
      params: [viewerId, postId],
    },
  ]);

  const row = read.rows[0];
  if (!row) return null;

  return {
    id: row.id,
    likes: row.likes,
    saves: row.saves,
    isLiked: row.is_liked,
    isSaved: row.is_saved,
  };
}

export async function countPosts(db: SqlClient): Promise<number> {
  const result = await db.query<{ total: number }>(
    'SELECT COUNT(*)::int AS total FROM posts',
  );
  return result.rows[0]?.total ?? 0;
}

const INSERT_POST = `
  INSERT INTO posts (
    id, video_url, author_id, author_handle, author_display_name,
    author_emoji, author_is_verified, caption, music
  )
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
  RETURNING *
`;

/**
 * Inserts a post and returns it in the same shape the feed serves, so a client that just
 * uploaded a clip can drop it straight into the top of the feed without a refetch.
 */
export async function createPost(
  db: SqlClient,
  input: CreatePostInput,
): Promise<PostPayload | null> {
  const id = `post-${crypto.randomUUID()}`;
  const authorId = input.authorId ?? `author-${crypto.randomUUID().slice(0, 8)}`;

  const inserted = await db.query<PostRow>(INSERT_POST, [
    id,
    input.videoUrl,
    authorId,
    input.authorHandle ?? '@you',
    input.authorDisplayName ?? 'You',
    input.authorEmoji ?? '📱',
    input.authorIsVerified ?? false,
    input.caption ?? '',
    input.music ?? 'original sound',
  ]);

  const row = inserted.rows[0];
  if (!row) return null;

  // The new post has no reactions yet, so the viewer specific flags are known to be false
  // without another round trip.
  return toPayload({ ...row, is_liked: false, is_saved: false });
}
