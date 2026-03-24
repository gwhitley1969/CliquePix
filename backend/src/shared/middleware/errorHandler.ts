import { HttpResponseInit } from '@azure/functions';
import { AppError } from '../utils/errors';
import { errorResponse } from '../utils/response';
import { trackError } from '../services/telemetryService';

export function handleError(error: unknown): HttpResponseInit {
  if (error instanceof AppError) {
    return errorResponse(error.code, error.message, error.statusCode);
  }

  if (error instanceof Error) {
    // Auth errors from middleware
    if (error.message === 'UNAUTHORIZED' || error.message === 'USER_NOT_FOUND') {
      return errorResponse('UNAUTHORIZED', 'Authentication required.', 401);
    }

    // JWT-specific errors
    if (error.name === 'JsonWebTokenError' || error.name === 'TokenExpiredError') {
      return errorResponse('UNAUTHORIZED', 'Invalid or expired token.', 401);
    }

    // Log unexpected errors
    trackError(error);
    console.error('Unhandled error:', error.message);
  }

  return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred.', 500);
}
