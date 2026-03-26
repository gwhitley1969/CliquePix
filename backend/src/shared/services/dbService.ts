import { Pool, PoolConfig } from 'pg';

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
