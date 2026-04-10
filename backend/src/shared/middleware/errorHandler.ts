import { HttpResponseInit } from '@azure/functions';
import { AppError } from '../utils/errors';
import { errorResponse } from '../utils/response';
import { trackError } from '../services/telemetryService';

export function handleError(error: unknown, invocationId?: string): HttpResponseInit {
  if (error instanceof AppError) {
    // Log AppErrors at warn level so they show up in App Insights traces.
    // Previously these were returned silently, making bug-hunting hard —
    // we'd see the client show "Upload failed" but have no backend trace.
    console.warn(
      `AppError: ${error.code} (status=${error.statusCode}) — ${error.message}`,
      invocationId ? `[${invocationId}]` : '',
    );
    return errorResponse(error.code, error.message, error.statusCode, invocationId);
  }

  if (error instanceof Error) {
    // JWT-specific errors
    if (error.name === 'JsonWebTokenError' || error.name === 'TokenExpiredError') {
      return errorResponse('UNAUTHORIZED', 'Invalid or expired token.', 401, invocationId);
    }

    // Log unexpected errors
    trackError(error, invocationId ? { invocationId } : undefined);
    console.error('Unhandled error:', error.name, error.constructor.name, invocationId ? `[${invocationId}]` : '');
  }

  return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred.', 500, invocationId);
}
