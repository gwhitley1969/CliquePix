import { ValidationError } from './errors';

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Intentionally matches control chars for input sanitization. Strip them
// from user-supplied strings before persisting to prevent terminal-escape
// attacks in logs/CLI output.
// eslint-disable-next-line no-control-regex
const CONTROL_CHAR_REGEX = /[\x00-\x1F\x7F]/g;

export function isValidUUID(value: string): boolean {
  return UUID_REGEX.test(value);
}

export function sanitizeString(value: string, maxLength: number): string {
  return value.replace(CONTROL_CHAR_REGEX, '').trim().slice(0, maxLength);
}

export function validateRequiredString(value: unknown, fieldName: string, maxLength = 100): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new ValidationError(`${fieldName} is required.`);
  }
  return sanitizeString(value, maxLength);
}

export function validateOptionalString(value: unknown, maxLength = 500): string | null {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string') {
    throw new ValidationError('Invalid string value.');
  }
  return sanitizeString(value, maxLength);
}

export function validateRetentionHours(value: unknown): 24 | 72 | 168 {
  if (value !== 24 && value !== 72 && value !== 168) {
    throw new ValidationError('retention_hours must be 24, 72, or 168.');
  }
  return value as 24 | 72 | 168;
}

export function validateReactionType(value: unknown): 'heart' | 'laugh' | 'fire' | 'wow' {
  const valid = ['heart', 'laugh', 'fire', 'wow'];
  if (typeof value !== 'string' || !valid.includes(value)) {
    throw new ValidationError('reaction_type must be heart, laugh, fire, or wow.');
  }
  return value as 'heart' | 'laugh' | 'fire' | 'wow';
}

export function validatePlatform(value: unknown): 'ios' | 'android' {
  if (value !== 'ios' && value !== 'android') {
    throw new ValidationError('platform must be ios or android.');
  }
  return value as 'ios' | 'android';
}

export function validateMimeType(value: unknown): 'image/jpeg' | 'image/png' {
  if (value !== 'image/jpeg' && value !== 'image/png') {
    throw new ValidationError('mime_type must be image/jpeg or image/png.');
  }
  return value as 'image/jpeg' | 'image/png';
}
