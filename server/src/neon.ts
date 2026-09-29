import { neon } from '@neondatabase/serverless';
import type { SqlClient, Statement } from './types';

const FULL_RESULTS = { fullResults: true } as const;

export function createNeonClient(databaseUrl: string): SqlClient {
  const sql = neon(databaseUrl);

  return {
    async query<Row>(text: string, params?: unknown[]) {
      const result = await sql.query(text, params ?? [], FULL_RESULTS);
      return { rows: result.rows as Row[], rowCount: result.rowCount };
    },
    async transaction<Row>(statements: Statement[]) {
      const queries = statements.map((statement: Statement) =>
        sql.query(statement.text, statement.params ?? []),
      );
      const results = await sql.transaction(queries, {
        fullResults: true,
        isolationLevel: 'ReadCommitted',
      });
      return results.map((result) => ({
        rows: result.rows as Row[],
        rowCount: result.rowCount,
      }));
    },
  };
}

export function createCachedNeonClient(): (url: string) => SqlClient {
  let cached: { url: string; client: SqlClient } | null = null;

  return (url: string) => {
    if (cached?.url !== url) {
      cached = { url, client: createNeonClient(url) };
    }
    return cached.client;
  };
}
