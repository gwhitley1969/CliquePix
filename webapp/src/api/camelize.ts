/**
 * Recursively converts snake_case object keys to camelCase. Used at the axios
 * response boundary so backend responses (which use PostgreSQL column names
 * like `created_at`, `external_auth_id`, `thumbnail_url`) match the TS types
 * in webapp/src/models which use idiomatic camelCase.
 *
 * Only transforms keys on plain objects and arrays; leaves primitive values
 * (strings, numbers, booleans, Date strings, URLs) untouched.
 */
function snakeToCamel(input: string): string {
  return input.replace(/_([a-z0-9])/g, (_, ch: string) => ch.toUpperCase());
}

export function camelize<T = unknown>(input: unknown): T {
  if (input === null || input === undefined) return input as T;
  if (Array.isArray(input)) {
    return input.map((item) => camelize(item)) as unknown as T;
  }
  if (typeof input === 'object' && (input as object).constructor === Object) {
    const source = input as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(source)) {
      out[snakeToCamel(key)] = camelize(source[key]);
    }
    return out as T;
  }
  return input as T;
}
