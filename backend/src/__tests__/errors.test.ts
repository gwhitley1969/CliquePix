import {
  AppError,
  NotFoundError,
  UnauthorizedError,
  ForbiddenError,
  ValidationError,
  ConflictError,
} from '../shared/utils/errors';

// ─── AppError ────────────────────────────────────────────────────────────────

describe('AppError', () => {
  it('creates an error with code, message, and statusCode', () => {
    const err = new AppError('CUSTOM_ERROR', 'Something went wrong', 422);
    expect(err.code).toBe('CUSTOM_ERROR');
    expect(err.message).toBe('Something went wrong');
    expect(err.statusCode).toBe(422);
    expect(err.name).toBe('AppError');
  });

  it('defaults to statusCode 400', () => {
    const err = new AppError('BAD', 'Bad request');
    expect(err.statusCode).toBe(400);
  });

  it('is an instance of Error', () => {
    const err = new AppError('TEST', 'test');
    expect(err).toBeInstanceOf(Error);
    expect(err).toBeInstanceOf(AppError);
  });
});

// ─── NotFoundError ───────────────────────────────────────────────────────────

describe('NotFoundError', () => {
  it('creates a 404 error with uppercased resource code', () => {
    const err = new NotFoundError('event');
    expect(err.code).toBe('EVENT_NOT_FOUND');
    expect(err.message).toBe('The requested event does not exist.');
    expect(err.statusCode).toBe(404);
  });

  it('works with multi-word resources', () => {
    const err = new NotFoundError('clique member');
    expect(err.code).toBe('CLIQUE MEMBER_NOT_FOUND');
    expect(err.message).toBe('The requested clique member does not exist.');
  });

  it('is an AppError', () => {
    expect(new NotFoundError('user')).toBeInstanceOf(AppError);
  });
});

// ─── UnauthorizedError ───────────────────────────────────────────────────────

describe('UnauthorizedError', () => {
  it('creates a 401 error with default message', () => {
    const err = new UnauthorizedError();
    expect(err.code).toBe('UNAUTHORIZED');
    expect(err.message).toBe('Authentication required.');
    expect(err.statusCode).toBe(401);
  });

  it('accepts a custom message', () => {
    const err = new UnauthorizedError('Token expired.');
    expect(err.message).toBe('Token expired.');
  });
});

// ─── ForbiddenError ──────────────────────────────────────────────────────────

describe('ForbiddenError', () => {
  it('creates a 403 error with default message', () => {
    const err = new ForbiddenError();
    expect(err.code).toBe('FORBIDDEN');
    expect(err.message).toBe('You do not have permission to perform this action.');
    expect(err.statusCode).toBe(403);
  });

  it('accepts a custom message', () => {
    const err = new ForbiddenError('Owners only.');
    expect(err.message).toBe('Owners only.');
  });
});

// ─── ValidationError ─────────────────────────────────────────────────────────

describe('ValidationError', () => {
  it('creates a 400 error', () => {
    const err = new ValidationError('Name is required.');
    expect(err.code).toBe('VALIDATION_ERROR');
    expect(err.message).toBe('Name is required.');
    expect(err.statusCode).toBe(400);
  });
});

// ─── ConflictError ───────────────────────────────────────────────────────────

describe('ConflictError', () => {
  it('creates a 409 error', () => {
    const err = new ConflictError('Already a member.');
    expect(err.code).toBe('CONFLICT');
    expect(err.message).toBe('Already a member.');
    expect(err.statusCode).toBe(409);
  });
});
