import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, URL as NodeURL } from 'node:url';
import type { QueryResult, SqlClient, Statement } from '../src/types';

// The workers types and the node types both declare URL, so the node one is named explicitly
// to keep fileURLToPath from receiving the incompatible global.
const read = (name: string) => readFile(fileURLToPath(new NodeURL(name, import.meta.url)), 'utf8');

export type TestDatabase = {
  db: SqlClient;
  reset(): Promise<void>;
  close(): Promise<void>;
};

/**
 * An in-memory stand in for R2.
 *
 * Only the parts the upload routes touch are implemented, and the slices are computed rather
 * than stored so a range request can be asserted on without a real bucket.
 */
export type FakeR2Bucket = R2Bucket & { readonly objects: Map<string, { body: Uint8Array; type: string }> };

export function createFakeR2Bucket(): FakeR2Bucket {
  const objects = new Map<string, { body: Uint8Array; type: string }>();

  const slice = (bytes: Uint8Array, range: R2Range): Uint8Array | null => {
    let start: number;
    let end: number;

    if ('suffix' in range) {
      if (range.suffix <= 0) return null;
      start = Math.max(bytes.length - range.suffix, 0);
      end = bytes.length - 1;
    } else {
      start = range.offset ?? 0;
      end = start + (range.length ?? bytes.length) - 1;
    }

    if (start >= bytes.length || end < start) return null;
    return bytes.slice(start, Math.min(end, bytes.length - 1) + 1);
  };

  const build = (key: string, range: R2Range | undefined, body: ReadableStream | null) => {
    const stored = objects.get(key);
    if (!stored || body === null) return null;

    const full = stored.body;
    // R2 throws on a range that falls outside the object rather than handing back nothing, and
    // the route has to turn that into a 416. Answering null here instead would let the real
    // behaviour go untested.
    if (range !== undefined) {
      const sliceOfRange = slice(full, range);
      if (!sliceOfRange) throw new RangeError('range not satisfiable');
      return assemble(key, full, stored.type, sliceOfRange, range);
    }
    return assemble(key, full, stored.type, full, range);
  };

  const assemble = (
    key: string,
    full: Uint8Array,
    type: string,
    sliceOfRange: Uint8Array,
    range: R2Range | undefined,
  ) => {
    // R2 always reports a range, even for a full read, so the fake does the same. The route
    // has to key off the request to answer 200 rather than 206.
    const resolved = {
      offset: range === undefined
        ? 0
        : 'suffix' in range
          ? Math.max(full.length - range.suffix, 0)
          : (range.offset ?? 0),
      length: sliceOfRange.length,
      size: sliceOfRange.length,
    };

    return {
      key,
      size: full.length,
      uploaded: new Date(0),
      httpMetadata: { contentType: type },
      body: new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(sliceOfRange);
          controller.close();
        },
      }),
      bodyUsed: false,
      arrayBuffer: async () => sliceOfRange.buffer.slice(
        sliceOfRange.byteOffset,
        sliceOfRange.byteOffset + sliceOfRange.byteLength,
      ) as ArrayBuffer,
      range: resolved,
    } as unknown as R2ObjectBody;
  };

  return {
    objects,
    async get(key: string, options?: R2GetOptions) {
      return build(key, options?.range as R2Range | undefined, {} as ReadableStream);
    },
    async head(key: string) {
      const stored = objects.get(key);
      if (!stored) return null;
      return {
        key,
        size: stored.body.length,
        uploaded: new Date(0),
        httpMetadata: { contentType: stored.type },
      } as unknown as R2Object;
    },
    async put(key: string, value: unknown, options?: R2PutOptions) {
      const bytes = value instanceof Uint8Array
        ? value
        : new Uint8Array(await new Response(value as BodyInit).arrayBuffer());
      const metadata = options?.httpMetadata;
      objects.set(key, {
        body: bytes,
        type: (metadata instanceof Headers ? metadata.get('content-type') : metadata?.contentType)
          ?? 'application/octet-stream',
      });
      return { key, size: bytes.length, uploaded: new Date(0) } as unknown as R2Object;
    },
    async delete() { return undefined; },
    async list() {
      return {
        objects: [...objects.keys()].map((key) => ({ key })),
        truncated: false,
      } as unknown as R2Objects;
    },
    async createMultipartUpload() { throw new Error('not implemented in tests'); },
    resumeMultipartUpload() { throw new Error('not implemented in tests'); },
  } as unknown as FakeR2Bucket;
}

export async function createTestDatabase(): Promise<TestDatabase> {  const pglite = await PGlite.create();
  await pglite.exec(await read('../migrations/0001_init.sql'));
  await pglite.exec(await read('../seed.sql'));

  const toResult = <Row>(result: { rows: unknown[]; affectedRows?: number }): QueryResult<Row> => ({
    rows: result.rows as Row[],
    rowCount: result.affectedRows ?? result.rows.length,
  });

  const db: SqlClient = {
    async query<Row>(text: string, params: unknown[] = []) {
      return toResult<Row>(await pglite.query<Row>(text, params as never[]));
    },
    async transaction<Row>(statements: Statement[]) {
      const results: QueryResult<Row>[] = [];
      for (const statement of statements) {
        results.push(
          toResult<Row>(await pglite.query<Row>(statement.text, (statement.params ?? []) as never[])),
        );
      }
      return results;
    },
  };

  return {
    db,
    reset: async () => {
      await pglite.exec(await read('../seed.sql'));
    },
    close: () => pglite.close(),
  };
}
