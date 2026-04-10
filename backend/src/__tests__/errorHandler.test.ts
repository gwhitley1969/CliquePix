import { handleError } from '../shared/middleware/errorHandler';
import {
  AppError,
  NotFoundError,
  UnauthorizedError,
  ForbiddenError,
  ValidationError,
  ConflictError,
} from '../shared/utils/errors';

// Mock telemetry to avoid side effects
jest.mock('../shared/services/telemetryService', () => ({
  trackError: jest.fn(),
}));

describe('handleError', () => {
  // ─── AppError subclasses ───────────────────────────────────────────────

  it('returns 404 for NotFoundError', () => {
    const response = handleError(new NotFoundError('event'));
    expect(response.status).toBe(404);
    expect((response.jsonBody as any).error.code).toBe('EVENT_NOT_FOUND');
    expect((response.jsonBody as any).data).toBeNull();
  });

  it('returns 401 for UnauthorizedError', () => {
    const response = handleError(new UnauthorizedError());
    expect(response.status).toBe(401);
    expect((response.jsonBody as any).error.code).toBe('UNAUTHORIZED');
  });

  it('returns 403 for ForbiddenError', () => {
    const response = handleError(new ForbiddenError());
    expect(response.status).toBe(403);
    expect((response.jsonBody as any).error.code).toBe('FORBIDDEN');
  });

  it('returns 400 for ValidationError', () => {
    const response = handleError(new ValidationError('Name is required.'));
    expect(response.status).toBe(400);
    expect((response.jsonBody as any).error.code).toBe('VALIDATION_ERROR');
    expect((response.jsonBody as any).error.message).toBe('Name is required.');
  });

  it('returns 409 for ConflictError', () => {
    const response = handleError(new ConflictError('Already exists.'));
    expect(response.status).toBe(409);
    expect((response.jsonBody as any).error.code).toBe('CONFLICT');
  });

  it('returns custom status for AppError', () => {
    const response = handleError(new AppError('VIDEO_LIMIT_REACHED', 'Too many videos.', 429));
    expect(response.status).toBe(429);
    expect((response.jsonBody as any).error.code).toBe('VIDEO_LIMIT_REACHED');
  });

  // ─── JWT errors ────────────────────────────────────────────────────────

  it('returns 401 for JsonWebTokenError', () => {
    const err = new Error('invalid signature');
    err.name = 'JsonWebTokenError';
    const response = handleError(err);
    expect(response.status).toBe(401);
    expect((response.jsonBody as any).error.code).toBe('UNAUTHORIZED');
  });

  it('returns 401 for TokenExpiredError', () => {
    const err = new Error('jwt expired');
    err.name = 'TokenExpiredError';
    const response = handleError(err);
    expect(response.status).toBe(401);
    expect((response.jsonBody as any).error.message).toBe('Invalid or expired token.');
  });

  // ─── Unknown errors ────────────────────────────────────────────────────

  it('returns 500 for generic Error', () => {
    const response = handleError(new Error('something broke'));
    expect(response.status).toBe(500);
    expect((response.jsonBody as any).error.code).toBe('INTERNAL_ERROR');
    expect((response.jsonBody as any).error.message).toBe('An unexpected error occurred.');
  });

  it('returns 500 for non-Error thrown value', () => {
    const response = handleError('a string error');
    expect(response.status).toBe(500);
    expect((response.jsonBody as any).error.code).toBe('INTERNAL_ERROR');
  });

  it('returns 500 for null', () => {
    const response = handleError(null);
    expect(response.status).toBe(500);
  });

  // ─── Response structure ────────────────────────────────────────────────

  it('always returns { data: null, error: { code, message } } structure', () => {
    const response = handleError(new ValidationError('Bad input'));
    const body = response.jsonBody as any;
    expect(body).toHaveProperty('data', null);
    expect(body).toHaveProperty('error');
    expect(body.error).toHaveProperty('code');
    expect(body.error).toHaveProperty('message');
  });

  it('never leaks internal error messages to client', () => {
    const response = handleError(new Error('database connection pool exhausted'));
    const body = response.jsonBody as any;
    expect(body.error.message).toBe('An unexpected error occurred.');
    expect(body.error.message).not.toContain('database');
  });
});
