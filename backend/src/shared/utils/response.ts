import { HttpResponseInit } from '@azure/functions';

export function successResponse(data: unknown, status = 200): HttpResponseInit {
  return {
    status,
    jsonBody: { data, error: null },
    headers: { 'Content-Type': 'application/json' },
  };
}

export function errorResponse(code: string, message: string, status = 400, requestId?: string): HttpResponseInit {
  return {
    status,
    jsonBody: {
      data: null,
      error: { code, message, ...(requestId ? { request_id: requestId } : {}) },
    },
    headers: { 'Content-Type': 'application/json' },
  };
}
