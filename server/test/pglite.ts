import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import type { QueryResult, SqlClient, Statement } from '../src/types';

const read = (name: string) => readFile(fileURLToPath(new URL(name, import.meta.url)), 'utf8');

export type TestDatabase = {
  db: SqlClient;
  reset(): Promise<void>;
  close(): Promise<void>;
};

export async function createTestDatabase(): Promise<TestDatabase> {
  const pglite = await PGlite.create();
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
