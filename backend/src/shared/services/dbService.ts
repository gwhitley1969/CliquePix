import { Pool, PoolConfig, types as pgTypes } from 'pg';

// ============================================================================
// Type parser overrides
// ============================================================================
// By default, node-postgres returns BIGINT (INT8, OID 20) as a STRING to avoid
// JavaScript's 2^53 integer precision limit. This is safe but causes silent
// bugs when TypeScript code treats it as `number` (e.g., strict equality
// `number !== string` is ALWAYS true regardless of value).
//
// For CliquePix, the only BIGINT column is `photos.file_size_bytes`, capped
// server-side at 500MB = 524,288,000 bytes. That's 17 orders of magnitude
// below Number.MAX_SAFE_INTEGER (9.007e+15), so converting to Number is safe.
//
// This fixes a real bug where commitVideoUpload's size-mismatch check always
// fired even when sizes matched, because `actualSize (number) !== file_size_bytes (string)`
// was always true. See videos.ts commitVideoUpload for the historical context.
pgTypes.setTypeParser(pgTypes.builtins.INT8, (val: string) => parseInt(val, 10));

let pool: Pool | null = null;

function getPool(): Pool {
  if (!pool) {
    const connectionString = process.env.PG_CONNECTION_STRING;
    if (!connectionString) {
      throw new Error('PG_CONNECTION_STRING is not configured');
    }
    const config: PoolConfig = {
      connectionString,
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      ssl: { rejectUnauthorized: true },
    };
    pool = new Pool(config);
    pool.on('error', (err) => {
      console.error('Unexpected pool error:', (err as NodeJS.ErrnoException).code ?? 'UNKNOWN');
    });
  }
  return pool;
}

export async function query<T>(text: string, params?: unknown[]): Promise<T[]> {
  const result = await getPool().query(text, params);
  return result.rows as T[];
}

export async function queryOne<T>(text: string, params?: unknown[]): Promise<T | null> {
  const result = await getPool().query(text, params);
  return (result.rows[0] as T) ?? null;
}

export async function execute(text: string, params?: unknown[]): Promise<number> {
  const result = await getPool().query(text, params);
  return result.rowCount ?? 0;
}
