import { Hono } from 'hono';
import type { Context } from 'hono';
import { cors } from 'hono/cors';
import { createCachedNeonClient } from './neon';
import {
  countPosts,
  createPost,
  decodeCursor,
  fetchFeed,
  setReaction,
} from './repository';
import {
  ALLOWED_VIDEO_EXTENSIONS,
  DEFAULT_VIEWER,
  MAX_UPLOAD_BYTES,
  VIEWER_HEADER,
  type Bindings,
  type CreatePostInput,
  type SqlClient,
} from './types';

type AppContext = Context<{ Bindings: Bindings }>;
type ClientResolver = (databaseUrl: string) => SqlClient;

const CAPTION_LIMIT = 500;
const HANDLE_LIMIT = 40;

export function createApp(resolve: ClientResolver) {
  const app = new Hono<{ Bindings: Bindings }>();

  app.use('/api/*', cors());

  const clientFor = (c: AppContext): SqlClient | null => {
    const databaseUrl = c.env.DATABASE_URL;
    return databaseUrl ? resolve(databaseUrl) : null;
  };

  const viewerOf = (c: AppContext): string => {
    const raw = c.req.header(VIEWER_HEADER)?.trim();
    return raw && raw.length > 0 ? raw.slice(0, 64) : DEFAULT_VIEWER;
  };

  const requireDatabase = (c: AppContext): SqlClient | Response => {
    const client = clientFor(c);
    if (!client) {
      return c.json({ error: 'database_not_configured' }, 503);
    }
    return client;
  };

  app.get('/api/health', async (c) => {
    const client = requireDatabase(c);
    if (client instanceof Response) return client;

    return c.json({ status: 'ok', posts: await countPosts(client) });
  });

  app.get('/api/feed', async (c) => {
    const client = requireDatabase(c);
    if (client instanceof Response) return client;

    const cursor = decodeCursor(c.req.query('cursor'));
    const rawLimit = c.req.query('limit');
    const page = await fetchFeed(
      client,
      viewerOf(c),
      cursor,
      rawLimit === undefined ? 0 : Number(rawLimit),
    );
    return c.json(page);
  });

  const react = (kind: 'post_likes' | 'post_saves') => async (c: AppContext) => {
    const client = requireDatabase(c);
    if (client instanceof Response) return client;

    const postId = c.req.param('id');
    if (!postId) {
      return c.json({ error: 'not_found' }, 404);
    }

    const enabled = c.req.method === 'POST';
    const result = await setReaction(client, kind, postId, viewerOf(c), enabled);

    if (!result) {
      return c.json({ error: 'post_not_found' }, 404);
    }
    return c.json(result);
  };

  app.post('/api/posts/:id/like', react('post_likes'));
  app.delete('/api/posts/:id/like', react('post_likes'));
  app.post('/api/posts/:id/save', react('post_saves'));
  app.delete('/api/posts/:id/save', react('post_saves'));

  /**
   * Stores an uploaded clip in R2 and hands back a URL the player can stream.
   *
   * The bucket is private, so the object is only reachable through this Worker, which means
   * an upload also works on a device that is not signed in and without opening public access
   * on the bucket.
   */
  app.post('/api/videos', async (c) => {
    const videos = c.env.VIDEOS;
    if (!videos) {
      return c.json({ error: 'uploads_not_configured' }, 503);
    }

    const form = await c.req.formData().catch(() => null);
    if (!form) {
      return c.json({ error: 'invalid_form_data' }, 400);
    }

    const file = form.get('video');
    if (!(file instanceof File)) {
      return c.json({ error: 'video_is_required' }, 400);
    }

    const extension = extensionOf(file.name);
    if (!ALLOWED_VIDEO_EXTENSIONS.includes(extension as (typeof ALLOWED_VIDEO_EXTENSIONS)[number])) {
      return c.json({ error: 'unsupported_format' }, 400);
    }

    if (file.size === 0) {
      return c.json({ error: 'video_is_empty' }, 400);
    }
    if (file.size > MAX_UPLOAD_BYTES) {
      return c.json({ error: 'video_too_large', maxBytes: MAX_UPLOAD_BYTES }, 413);
    }

    const key = `videos/${crypto.randomUUID()}.${extension}`;
    // Streamed rather than buffered so a large clip does not have to fit in the isolate.
    await videos.put(key, file.stream(), {
      httpMetadata: { contentType: file.type || contentTypeFor(extension) },
    });

    return c.json({
      key,
      url: `/api/videos/${key.split('/').pop()}`,
      size: file.size,
    }, 201);
  });

  /**
   * Streams a stored clip. Ranges are forwarded to R2 so AVPlayer can seek without
   * downloading the whole file.
   */
  app.get('/api/videos/:key', async (c) => {
    const videos = c.env.VIDEOS;
    if (!videos) {
      return c.json({ error: 'uploads_not_configured' }, 503);
    }

    const name = c.req.param('key');
    if (!name || name.includes('/') || name.includes('..')) {
      return c.json({ error: 'not_found' }, 404);
    }

    const range = parseRange(c.req.header('Range'));
    if (range === null) {
      return new Response(null, { status: 416, headers: withType(new Headers(), typeFor(name)) });
    }

    // The range is resolved by R2 rather than sliced here, so seeking does not pull the whole
    // clip through the isolate.
    const object = range === undefined
      ? await videos.get(`videos/${name}`)
      : await videos.get(`videos/${name}`, { range });
    if (!object) {
      return c.json({ error: 'not_found' }, 404);
    }

    const headers = withType(new Headers(), object.httpMetadata?.contentType ?? typeFor(name));

    // R2 reports a range even for a full read, so the status follows the request rather than
    // the shape of the response: only an actual Range request earns a 206.
    const resolved = range === undefined ? null : resolvedRange(object);
    if (resolved) {
      headers.set('Content-Range', contentRangeHeader(resolved, object.size));
      headers.set('Content-Length', String(resolved.size));
      return new Response(object.body, { status: 206, headers });
    }

    headers.set('Content-Length', String(object.size));
    return new Response(object.body, { status: 200, headers });
  });

  app.post('/api/posts', async (c) => {
    const client = requireDatabase(c);
    if (client instanceof Response) return client;

    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== 'object') {
      return c.json({ error: 'invalid_json' }, 400);
    }

    const input = (body as Record<string, unknown>).videoUrl;
    if (typeof input !== 'string' || !isAllowedVideoUrl(input, c)) {
      return c.json({ error: 'invalid_video_url' }, 400);
    }

    const caption = readString(body, 'caption', CAPTION_LIMIT);
    if (!caption.ok) {
      return c.json({ error: 'invalid_caption', maxLength: CAPTION_LIMIT }, 400);
    }

    const music = readString(body, 'music', 120);
    if (!music.ok) {
      return c.json({ error: 'invalid_music', maxLength: 120 }, 400);
    }

    const authorHandle = readString(body, 'authorHandle', HANDLE_LIMIT);
    if (!authorHandle.ok) {
      return c.json({ error: 'invalid_author_handle', maxLength: HANDLE_LIMIT }, 400);
    }

    const displayName = readString(body, 'authorDisplayName', HANDLE_LIMIT);
    if (!displayName.ok) {
      return c.json({ error: 'invalid_author_display_name', maxLength: HANDLE_LIMIT }, 400);
    }

    const emoji = readString(body, 'authorEmoji', 8);
    if (!emoji.ok) {
      return c.json({ error: 'invalid_author_emoji', maxLength: 8 }, 400);
    }

    const verified = body.authorIsVerified;
    if (verified !== undefined && typeof verified !== 'boolean') {
      return c.json({ error: 'invalid_author_is_verified' }, 400);
    }

    const created: CreatePostInput = {
      videoUrl: input,
      caption: caption.value ?? '',
      music: music.value ?? 'original sound',
      authorHandle: authorHandle.value,
      authorDisplayName: displayName.value,
      authorEmoji: emoji.value,
      authorIsVerified: verified as boolean | undefined,
    };

    const post = await createPost(client, created);
    if (!post) {
      return c.json({ error: 'post_not_created' }, 500);
    }
    return c.json(post, 201);
  });

  app.notFound((c) => c.json({ error: 'not_found' }, 404));

  app.onError((error, c) => {
    console.error(error);
    return c.json({ error: 'internal_error' }, 500);
  });

  return app;
}

function extensionOf(name: string): string {
  const index = name.lastIndexOf('.');
  return index === -1 ? '' : name.slice(index + 1).toLowerCase();
}

function contentTypeFor(extension: string): string {
  switch (extension) {
    case 'mov':
      return 'video/quicktime';
    case 'm4v':
      return 'video/x-m4v';
    default:
      return 'video/mp4';
  }
}

const typeFor = (name: string): string => contentTypeFor(extensionOf(name));

/**
 * Turns a Range header into an R2 range.
 *
 * Only a single range is honoured: answering the multipart/byteranges form would mean prefixing
 * each part onto the body, and no media client asks for it. `null` means unsatisfiable and
 * `undefined` means no range was asked for.
 */
function parseRange(header: string | undefined): R2Range | undefined | null {
  if (!header) return undefined;

  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match) return null;

  const [, rawStart, rawEnd] = match;
  if (rawStart === '' && rawEnd === '') return null;

  if (rawStart === '') {
    // Suffix form: the last N bytes.
    const suffix = Number(rawEnd);
    return suffix > 0 ? { suffix } : null;
  }

  const start = Number(rawStart);
  const end = rawEnd === '' ? undefined : Number(rawEnd);
  if (!Number.isInteger(start) || start < 0) return null;
  if (end !== undefined && (!Number.isInteger(end) || end < start)) return null;

  return end === undefined ? { offset: start } : { offset: start, length: end - start + 1 };
}

type ResolvedRange = { start: number; end: number; size: number };

/**
 * Normalises whatever R2 hands back on a ranged read into explicit bounds.
 *
 * The runtime reports the byte count of the slice, but the published type only describes the
 * request, so the length is derived from the bounds when it is missing.
 */
function resolvedRange(object: R2ObjectBody): ResolvedRange | null {
  const range = object.range as ({ offset?: number; length?: number; size?: number } | undefined);
  if (!range) return null;

  const size = range.size
    ?? (range.length !== undefined
      ? range.length
      : object.size - (range.offset ?? 0));

  const start = range.offset ?? 0;
  return { start, end: start + size - 1, size };
}

function contentRangeHeader(range: ResolvedRange, totalSize: number): string {
  return `bytes ${range.start}-${range.end}/${totalSize}`;
}

function withType(headers: Headers, type: string): Headers {
  headers.set('Content-Type', type);
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return headers;
}

/**
 * Only clips this API stored are accepted.
 *
 * The bucket is private and everything is streamed back through /api/videos, so matching that
 * path keeps a post from pointing the feed at a third-party host that would otherwise learn who
 * is watching. The relative form the upload route hands back and the absolute form a client
 * builds from it both resolve to the same path.
 */
function isAllowedVideoUrl(value: string, c: AppContext): boolean {
  let url: URL;
  try {
    url = new URL(value, c.req.url);
  } catch {
    return false;
  }

  return url.pathname.startsWith('/api/videos/');
}

/**
 * Reads an optional string field, distinguishing "not supplied" from "supplied but unusable".
 *
 * Absent collapses to null, and anything that is present but not a string within the limit is
 * rejected so a caller cannot sneak a number or an over-long caption past the default.
 */
function readString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): { ok: true; value?: string } | { ok: false } {
  const value = body[key];
  if (value === undefined || value === null) return { ok: true };
  if (typeof value !== 'string') return { ok: false };
  return value.length <= maxLength ? { ok: true, value } : { ok: false };
}

export default createApp(createCachedNeonClient());
