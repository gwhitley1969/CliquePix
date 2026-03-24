import { HttpResponseInit } from '@azure/functions';

export function successResponse(data: unknown, status = 200): HttpResponseInit {
  return {
    status,
    jsonBody: { data, error: null },
    headers: { 'Content-Type': 'application/json' },
  };
}

export function errorResponse(code: string, message: string, status = 400): HttpResponseInit {
  return {
    status,
    jsonBody: { data: null, error: { code, message } },
    headers: { 'Content-Type': 'application/json' },
  };
}
