import { Hono } from 'hono';
import type { Context } from 'hono';
import { cors } from 'hono/cors';
import { createCachedNeonClient } from './neon';
import { countPosts, decodeCursor, fetchFeed, setReaction } from './repository';
import { DEFAULT_VIEWER, VIEWER_HEADER, type Bindings, type SqlClient } from './types';

type AppContext = Context<{ Bindings: Bindings }>;
type ClientResolver = (databaseUrl: string) => SqlClient;

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

  app.notFound((c) => c.json({ error: 'not_found' }, 404));

  app.onError((error, c) => {
    console.error(error);
    return c.json({ error: 'internal_error' }, 500);
  });

  return app;
}

export default createApp(createCachedNeonClient());
