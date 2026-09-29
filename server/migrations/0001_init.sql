-- Marauders feed schema (PostgreSQL, targets Neon)

CREATE TABLE IF NOT EXISTS posts (
  seq                 INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id                  TEXT        NOT NULL UNIQUE,
  video_url           TEXT        NOT NULL,
  author_id           TEXT        NOT NULL,
  author_handle       TEXT        NOT NULL,
  author_display_name TEXT        NOT NULL,
  author_emoji        TEXT        NOT NULL,
  author_is_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
  caption             TEXT        NOT NULL,
  music               TEXT        NOT NULL,
  likes               INTEGER     NOT NULL DEFAULT 0,
  comments_count      INTEGER     NOT NULL DEFAULT 0,
  saves               INTEGER     NOT NULL DEFAULT 0,
  shares              INTEGER     NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_posts_seq ON posts (seq DESC);

CREATE TABLE IF NOT EXISTS post_likes (
  viewer_id  TEXT        NOT NULL,
  post_id    TEXT        NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (viewer_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_post_id ON post_likes (post_id);

CREATE TABLE IF NOT EXISTS post_saves (
  viewer_id  TEXT        NOT NULL,
  post_id    TEXT        NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (viewer_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_post_saves_post_id ON post_saves (post_id);
