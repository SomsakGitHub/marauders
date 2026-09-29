import { readFile } from 'node:fs/promises';
import { neon } from '@neondatabase/serverless';

const splitStatements = (sql) => {
  const statements = [];
  let current = '';
  let inString = false;
  let inComment = false;

  for (let i = 0; i < sql.length; i += 1) {
    const char = sql[i];
    const next = sql[i + 1];

    if (inComment) {
      if (char === '\n') inComment = false;
      current += char;
      continue;
    }

    if (inString) {
      current += char;
      if (char === "'" && next === "'") {
        current += next;
        i += 1;
      } else if (char === "'") {
        inString = false;
      }
      continue;
    }

    if (char === '-' && next === '-') {
      inComment = true;
      current += char;
      continue;
    }

    if (char === "'") {
      inString = true;
      current += char;
      continue;
    }

    if (char === ';') {
      if (current.trim()) statements.push(current.trim());
      current = '';
      continue;
    }

    current += char;
  }

  if (current.trim()) statements.push(current.trim());
  return statements;
};

const databaseUrl = async () => {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;

  const vars = await readFile(new URL('../.dev.vars', import.meta.url), 'utf8');
  const match = vars.match(/^\s*DATABASE_URL\s*=\s*["']?(.+?)["']?\s*$/m);
  if (!match) {
    throw new Error('No DATABASE_URL found. Set it in .dev.vars or the environment.');
  }
  return match[1];
};

const run = async (file) => {
  const url = await databaseUrl();
  const sql = neon(url);
  const source = await readFile(new URL(`../${file}`, import.meta.url), 'utf8');
  const statements = splitStatements(source);

  process.stdout.write(`${file}: ${statements.length} statements\n`);

  for (const [index, statement] of statements.entries()) {
    try {
      await sql.query(statement);
    } catch (error) {
      process.stderr.write(`\nstatement ${index + 1} failed:\n${statement}\n\n${error.message}\n`);
      throw error;
    }
  }

  process.stdout.write(`${file}: done\n`);
};

const [command, file] = process.argv.slice(2);

if (command === 'migrate') {
  await run('migrations/0001_init.sql');
} else if (command === 'seed') {
  await run('seed.sql');
} else {
  process.stderr.write('usage: node scripts/db.mjs <migrate|seed>\n');
  process.exit(1);
}
