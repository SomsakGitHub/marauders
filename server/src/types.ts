export type Bindings = {
  DATABASE_URL: string;
  VIDEOS: R2Bucket;
  CF_ACCOUNT_ID?: string;
  /** Shared secret required by the write endpoints. Set with `wrangler secret put`. */
  UPLOAD_TOKEN?: string;
};

export type QueryResult<Row = Record<string, unknown>> = {
  rows: Row[];
  rowCount: number;
};

export type Statement = {
  text: string;
  params?: unknown[];
};

export type SqlClient = {
  query<Row = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<QueryResult<Row>>;
  transaction<Row = Record<string, unknown>>(
    statements: Statement[],
  ): Promise<QueryResult<Row>[]>;
};

export type PostRow = {
  seq: number;
  id: string;
  video_url: string;
  author_id: string;
  author_handle: string;
  author_display_name: string;
  author_emoji: string;
  author_is_verified: boolean;
  caption: string;
  music: string;
  likes: number;
  comments_count: number;
  saves: number;
  shares: number;
  is_liked: boolean;
  is_saved: boolean;
};

export type AuthorPayload = {
  id: string;
  handle: string;
  displayName: string;
  emoji: string;
  isVerified: boolean;
};

export type PostPayload = {
  id: string;
  videoUrl: string;
  author: AuthorPayload;
  caption: string;
  music: string;
  likes: number;
  comments: number;
  saves: number;
  shares: number;
  isLiked: boolean;
  isSaved: boolean;
};

export type FeedPage = {
  items: PostPayload[];
  nextCursor: string | null;
};

export type CreatePostInput = {
  videoUrl: string;
  caption?: string;
  music?: string;
  authorId?: string;
  authorHandle?: string;
  authorDisplayName?: string;
  authorEmoji?: string;
  authorIsVerified?: boolean;
};

export type ReactionResult = {
  id: string;
  likes: number;
  saves: number;
  isLiked: boolean;
  isSaved: boolean;
};

export const VIEWER_HEADER = 'x-viewer-id';
export const DEFAULT_VIEWER = 'anonymous';
export const MAX_PAGE_SIZE = 20;
export const DEFAULT_PAGE_SIZE = 5;

export const MAX_UPLOAD_BYTES = 64 * 1024 * 1024;
export const ALLOWED_VIDEO_EXTENSIONS = ['mp4', 'mov', 'm4v'] as const;
