import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/index';
import { createFakeR2Bucket, createTestDatabase, type FakeR2Bucket, type TestDatabase } from './pglite';

const TOKEN = 'test-upload-token';
const ENV_BASE = { DATABASE_URL: 'postgres://unused/test', UPLOAD_TOKEN: TOKEN };
const WRITE_HEADERS = { 'x-upload-token': TOKEN };
const STORED_URL = 'http://local/api/videos/';

let harness: TestDatabase;
let videos: FakeR2Bucket;
let app: ReturnType<typeof createApp>;

beforeAll(async () => {
  harness = await createTestDatabase();
  videos = createFakeR2Bucket();
  app = createApp(() => harness.db);
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await harness.reset();
  videos.objects.clear();
});

const upload = async (name: string, type = 'video/mp4', body = 'fake-mp4-bytes', token: string | null = TOKEN) => {
  const form = new FormData();
  form.append('video', new File([body], name, { type }));
  const headers: Record<string, string> = {};
  if (token !== null) headers['x-upload-token'] = token;
  return app.request(
    'http://local/api/videos',
    { method: 'POST', body: form, headers },
    { ...ENV_BASE, VIDEOS: videos },
  );
};

const countRows = async () => {
  const result = await harness.db.query<{ count: number }>('select count(*)::int as count from posts');
  return result.rows[0]?.count ?? 0;
};

const createPost = async (body: unknown, token: string | null = TOKEN) => {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== null) headers['x-upload-token'] = token;
  const response = await app.request(
    'http://local/api/posts',
    {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    },
    ENV_BASE,
  );
  return { status: response.status, body: await response.json() as Record<string, never> };
};

describe('POST /api/videos', () => {
  it('stores the clip and returns a URL that streams it back', async () => {
    const response = await upload('clip.mp4');
    const body = await response.json() as { key: string; url: string; size: number };

    expect(response.status).toBe(201);
    expect(body.key).toMatch(/^videos\/[0-9a-f-]+\.mp4$/);
    expect(body.url).toBe(`/api/videos/${body.key.split('/').pop()}`);
    expect(body.size).toBe('fake-mp4-bytes'.length);
    expect(videos.objects.has(body.key)).toBe(true);

    const played = await app.request(`http://local${body.url}`, undefined, { ...ENV_BASE, VIDEOS: videos });
    expect(played.status).toBe(200);
    expect(played.headers.get('Content-Type')).toBe('video/mp4');
    expect(await played.text()).toBe('fake-mp4-bytes');
  });

  it('rejects a request with no file', async () => {
    const response = await app.request(
      'http://local/api/videos',
      { method: 'POST', body: new FormData(), headers: WRITE_HEADERS },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'video_is_required' });
  });

  it('rejects a format that is not a video container', async () => {
    const response = await upload('payload.exe', 'application/octet-stream');

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'unsupported_format' });
  });

  it('rejects an empty file', async () => {
    const response = await upload('empty.mp4', 'video/mp4', '');

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'video_is_empty' });
  });

  it('503s when the bucket is not bound', async () => {
    const response = await app.request(
      'http://local/api/videos',
      {
        method: 'POST',
        body: (() => { const f = new FormData(); f.append('video', new File(['x'], 'a.mp4')); return f; })(),
        headers: WRITE_HEADERS,
      },
      ENV_BASE,
    );

    expect(response.status).toBe(503);
  });
});

describe('write access', () => {
  it('refuses an upload with no token and stores nothing', async () => {
    const response = await upload('clip.mp4', 'video/mp4', 'bytes', null);

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'unauthorized' });
    expect(videos.objects.size).toBe(0);
  });

  it('refuses an upload carrying the wrong token', async () => {
    const response = await upload('clip.mp4', 'video/mp4', 'bytes', 'nope');

    expect(response.status).toBe(401);
    expect(videos.objects.size).toBe(0);
  });

  it('refuses to create a post with no token', async () => {
    const before = await countRows();
    const { status, body } = await createPost({ videoUrl: `${STORED_URL}a.mp4` }, null);

    expect(status).toBe(401);
    expect(body).toEqual({ error: 'unauthorized' });
    expect(await countRows()).toBe(before);
  });

  it('checks the token before the database, so an unconfigured Worker is still refused', async () => {
    const bare = createApp(() => { throw new Error('must not be called'); });
    const form = new FormData();
    form.append('video', new File(['bytes'], 'clip.mp4', { type: 'video/mp4' }));

    const response = await bare.request(
      'http://local/api/videos',
      { method: 'POST', body: form },
      { VIDEOS: videos } as never,
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'uploads_not_configured' });
  });

  it('leaves the read routes open, since the feed is meant to be public', async () => {
    const health = await app.request('http://local/api/health', undefined, ENV_BASE);
    const feed = await app.request('http://local/api/feed', undefined, ENV_BASE);

    expect(health.status).toBe(200);
    expect(feed.status).toBe(200);
  });

  it('streams a stored clip back without a token', async () => {
    const uploaded = await upload('clip.mp4', 'video/mp4', '0123456789');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(`http://local${url}`, undefined, { ...ENV_BASE, VIDEOS: videos });

    expect(response.status).toBe(200);
    expect(await response.text()).toBe('0123456789');
  });
});

describe('GET /api/videos/:key', () => {
  it('answers a plain request with 200 rather than a partial response', async () => {
    const uploaded = await upload('clip.mp4', 'video/mp4', '0123456789');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(`http://local${url}`, undefined, { ...ENV_BASE, VIDEOS: videos });

    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Range')).toBeNull();
    expect(response.headers.get('Content-Length')).toBe('10');
    expect(await response.text()).toBe('0123456789');
  });

  it('answers a range request with 206 and the right slice', async () => {
    const uploaded = await upload('clip.mp4', 'video/mp4', '0123456789');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(
      `http://local${url}`,
      { headers: { Range: 'bytes=2-5' } },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(206);
    expect(response.headers.get('Content-Range')).toBe('bytes 2-5/10');
    expect(response.headers.get('Content-Length')).toBe('4');
    expect(await response.text()).toBe('2345');
  });

  it('answers a suffix range with the tail of the clip', async () => {
    const uploaded = await upload('clip.mp4', 'video/mp4', '0123456789');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(
      `http://local${url}`,
      { headers: { Range: 'bytes=-3' } },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(206);
    expect(response.headers.get('Content-Range')).toBe('bytes 7-9/10');
    expect(await response.text()).toBe('789');
  });

  it('rejects a malformed range with 416', async () => {
    const uploaded = await upload('clip.mp4');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(
      `http://local${url}`,
      { headers: { Range: 'bytes=abc' } },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(416);
  });

  it('answers a range past the end of the clip with 416, not a server error', async () => {
    // A range can parse cleanly and still fall outside the object. R2 rejects those, and the
    // answer has to be the RFC's 416 rather than the 500 that a thrown error would otherwise
    // become.
    const uploaded = await upload('clip.mp4', 'video/mp4', '0123456789');
    const { url } = await uploaded.json() as { url: string };

    const response = await app.request(
      `http://local${url}`,
      { headers: { Range: 'bytes=99999999-' } },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(416);
    expect(response.headers.get('Content-Range')).toBe('bytes */10');
    expect(response.headers.get('Accept-Ranges')).toBe('bytes');
  });

  it('still 404s a ranged read of a clip that does not exist', async () => {
    // The same null on a ranged read has to stay a 404 when there is no object behind it.
    const response = await app.request(
      'http://local/api/videos/missing.mp4',
      { headers: { Range: 'bytes=0-3' } },
      { ...ENV_BASE, VIDEOS: videos },
    );

    expect(response.status).toBe(404);
  });

  it('404s an unknown clip and refuses to walk out of the prefix', async () => {
    const missing = await app.request('http://local/api/videos/nope.mp4', undefined, { ...ENV_BASE, VIDEOS: videos });
    const traversal = await app.request('http://local/api/videos/..%2F..%2Fseed.sql', undefined, { ...ENV_BASE, VIDEOS: videos });

    expect(missing.status).toBe(404);
    expect(traversal.status).toBe(404);
  });
});

describe('POST /api/posts', () => {
  it('creates a post that appears at the top of the feed', async () => {
    const { status, body } = await createPost({ videoUrl: `${STORED_URL}clip.mp4`, caption: 'ทดสอบ' });

    expect(status).toBe(201);
    const post = body as unknown as { id: string; videoUrl: string; caption: string; likes: number };

    expect(post.id).toMatch(/^post-/);
    expect(post.videoUrl).toBe(`${STORED_URL}clip.mp4`);
    expect(post.caption).toBe('ทดสอบ');
    expect(post.likes).toBe(0);

    const feed = await app.request('http://local/api/feed?limit=1', undefined, ENV_BASE);
    const page = await feed.json() as { items: { id: string }[] };

    expect(page.items[0].id).toBe(post.id);
  });

  it('rejects a video URL this API did not store', async () => {
    const external = await createPost({ videoUrl: 'https://example.com/clip.mp4' });
    const local = await createPost({ videoUrl: '/api/videos/clip.mp4' });
    const insecure = await createPost({ videoUrl: 'http://127.0.0.1/clip.mp4' });

    expect(external.status).toBe(400);
    expect(local.status).toBe(201);
    expect(insecure.status).toBe(400);
  });

  it('rejects a caption over the limit and a non-string caption', async () => {
    const long = await createPost({ videoUrl: `${STORED_URL}a.mp4`, caption: 'x'.repeat(501) });
    const wrongType = await createPost({ videoUrl: `${STORED_URL}a.mp4`, caption: 42 });

    expect(long.status).toBe(400);
    expect(wrongType.status).toBe(400);
  });

  it('rejects a body that is not an object', async () => {
    const response = await app.request(
      'http://local/api/posts',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...WRITE_HEADERS },
        body: '"nope"',
      },
      ENV_BASE,
    );

    expect(response.status).toBe(400);
  });

  it('503s without a database rather than creating anything', async () => {
    const bare = createApp(() => {
      throw new Error('must not be called');
    });

    const response = await bare.request(
      'http://local/api/posts',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...WRITE_HEADERS },
        body: JSON.stringify({ videoUrl: `${STORED_URL}a.mp4` }),
      },
      { UPLOAD_TOKEN: TOKEN } as never,
    );

    expect(response.status).toBe(503);
  });
});
