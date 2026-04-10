import {
  isValidUUID,
  sanitizeString,
  validateRequiredString,
  validateOptionalString,
  validateRetentionHours,
  validateReactionType,
  validatePlatform,
  validateMimeType,
} from '../shared/utils/validators';
import { ValidationError } from '../shared/utils/errors';

// ─── isValidUUID ─────────────────────────────────────────────────────────────

describe('isValidUUID', () => {
  it('accepts a valid lowercase UUID', () => {
    expect(isValidUUID('550e8400-e29b-41d4-a716-446655440000')).toBe(true);
  });

  it('accepts a valid uppercase UUID', () => {
    expect(isValidUUID('550E8400-E29B-41D4-A716-446655440000')).toBe(true);
  });

  it('accepts a valid mixed-case UUID', () => {
    expect(isValidUUID('550e8400-E29B-41d4-a716-446655440000')).toBe(true);
  });

  it('rejects an empty string', () => {
    expect(isValidUUID('')).toBe(false);
  });

  it('rejects a random string', () => {
    expect(isValidUUID('not-a-uuid')).toBe(false);
  });

  it('rejects a UUID without hyphens', () => {
    expect(isValidUUID('550e8400e29b41d4a716446655440000')).toBe(false);
  });

  it('rejects a UUID with wrong segment lengths', () => {
    expect(isValidUUID('550e840-0e29b-41d4-a716-446655440000')).toBe(false);
  });

  it('rejects a UUID with invalid characters', () => {
    expect(isValidUUID('550e8400-e29b-41d4-a716-44665544000g')).toBe(false);
  });
});

// ─── sanitizeString ──────────────────────────────────────────────────────────

describe('sanitizeString', () => {
  it('passes through a normal string', () => {
    expect(sanitizeString('Hello World', 100)).toBe('Hello World');
  });

  it('strips control characters', () => {
    expect(sanitizeString('Hello\x00World\x1F', 100)).toBe('HelloWorld');
  });

  it('trims whitespace', () => {
    expect(sanitizeString('  Hello  ', 100)).toBe('Hello');
  });

  it('truncates to maxLength', () => {
    expect(sanitizeString('Hello World', 5)).toBe('Hello');
  });

  it('strips control chars before truncating', () => {
    expect(sanitizeString('\x00AB\x01CD', 3)).toBe('ABC');
  });

  it('handles empty string', () => {
    expect(sanitizeString('', 100)).toBe('');
  });
});

// ─── validateRequiredString ──────────────────────────────────────────────────

describe('validateRequiredString', () => {
  it('returns sanitized string for valid input', () => {
    expect(validateRequiredString('Beach Trip', 'name')).toBe('Beach Trip');
  });

  it('trims and sanitizes', () => {
    expect(validateRequiredString('  Beach Trip\x00  ', 'name')).toBe('Beach Trip');
  });

  it('throws for empty string', () => {
    expect(() => validateRequiredString('', 'name')).toThrow(ValidationError);
    expect(() => validateRequiredString('', 'name')).toThrow('name is required.');
  });

  it('throws for whitespace-only string', () => {
    expect(() => validateRequiredString('   ', 'name')).toThrow(ValidationError);
  });

  it('throws for null', () => {
    expect(() => validateRequiredString(null, 'name')).toThrow(ValidationError);
  });

  it('throws for undefined', () => {
    expect(() => validateRequiredString(undefined, 'name')).toThrow(ValidationError);
  });

  it('throws for number', () => {
    expect(() => validateRequiredString(42, 'name')).toThrow(ValidationError);
  });

  it('truncates to default maxLength of 100', () => {
    const long = 'A'.repeat(150);
    expect(validateRequiredString(long, 'name').length).toBe(100);
  });

  it('truncates to custom maxLength', () => {
    expect(validateRequiredString('Hello World', 'name', 5)).toBe('Hello');
  });
});

// ─── validateOptionalString ──────────────────────────────────────────────────

describe('validateOptionalString', () => {
  it('returns sanitized string for valid input', () => {
    expect(validateOptionalString('A description')).toBe('A description');
  });

  it('returns null for null', () => {
    expect(validateOptionalString(null)).toBeNull();
  });

  it('returns null for undefined', () => {
    expect(validateOptionalString(undefined)).toBeNull();
  });

  it('returns null for empty string', () => {
    expect(validateOptionalString('')).toBeNull();
  });

  it('throws for non-string value', () => {
    expect(() => validateOptionalString(42)).toThrow(ValidationError);
  });

  it('truncates to default maxLength of 500', () => {
    const long = 'B'.repeat(600);
    expect(validateOptionalString(long)!.length).toBe(500);
  });
});

// ─── validateRetentionHours ──────────────────────────────────────────────────

describe('validateRetentionHours', () => {
  it('accepts 24', () => {
    expect(validateRetentionHours(24)).toBe(24);
  });

  it('accepts 72', () => {
    expect(validateRetentionHours(72)).toBe(72);
  });

  it('accepts 168', () => {
    expect(validateRetentionHours(168)).toBe(168);
  });

  it('rejects 0', () => {
    expect(() => validateRetentionHours(0)).toThrow(ValidationError);
  });

  it('rejects 48', () => {
    expect(() => validateRetentionHours(48)).toThrow(ValidationError);
  });

  it('rejects string "24"', () => {
    expect(() => validateRetentionHours('24')).toThrow(ValidationError);
  });

  it('rejects null', () => {
    expect(() => validateRetentionHours(null)).toThrow(ValidationError);
  });
});

// ─── validateReactionType ────────────────────────────────────────────────────

describe('validateReactionType', () => {
  it.each(['heart', 'laugh', 'fire', 'wow'] as const)('accepts "%s"', (type) => {
    expect(validateReactionType(type)).toBe(type);
  });

  it('rejects unknown reaction type', () => {
    expect(() => validateReactionType('like')).toThrow(ValidationError);
  });

  it('rejects empty string', () => {
    expect(() => validateReactionType('')).toThrow(ValidationError);
  });

  it('rejects number', () => {
    expect(() => validateReactionType(1)).toThrow(ValidationError);
  });
});

// ─── validatePlatform ────────────────────────────────────────────────────────

describe('validatePlatform', () => {
  it('accepts "ios"', () => {
    expect(validatePlatform('ios')).toBe('ios');
  });

  it('accepts "android"', () => {
    expect(validatePlatform('android')).toBe('android');
  });

  it('rejects "web"', () => {
    expect(() => validatePlatform('web')).toThrow(ValidationError);
  });

  it('rejects "iOS" (case sensitive)', () => {
    expect(() => validatePlatform('iOS')).toThrow(ValidationError);
  });

  it('rejects null', () => {
    expect(() => validatePlatform(null)).toThrow(ValidationError);
  });
});

// ─── validateMimeType ────────────────────────────────────────────────────────

describe('validateMimeType', () => {
  it('accepts "image/jpeg"', () => {
    expect(validateMimeType('image/jpeg')).toBe('image/jpeg');
  });

  it('accepts "image/png"', () => {
    expect(validateMimeType('image/png')).toBe('image/png');
  });

  it('rejects "image/gif"', () => {
    expect(() => validateMimeType('image/gif')).toThrow(ValidationError);
  });

  it('rejects "image/webp"', () => {
    expect(() => validateMimeType('image/webp')).toThrow(ValidationError);
  });

  it('rejects "video/mp4"', () => {
    expect(() => validateMimeType('video/mp4')).toThrow(ValidationError);
  });
});
