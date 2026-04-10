import { successResponse, errorResponse } from '../shared/utils/response';

describe('successResponse', () => {
  it('wraps data in standard envelope', () => {
    const response = successResponse({ id: '123', name: 'Test' });
    expect(response.status).toBe(200);
    expect((response.jsonBody as any).data).toEqual({ id: '123', name: 'Test' });
    expect((response.jsonBody as any).error).toBeNull();
  });

  it('accepts custom status code', () => {
    const response = successResponse(null, 201);
    expect(response.status).toBe(201);
  });

  it('sets Content-Type header', () => {
    const response = successResponse({});
    expect((response.headers as Record<string, string>)['Content-Type']).toBe('application/json');
  });

  it('handles array data', () => {
    const response = successResponse([1, 2, 3]);
    expect((response.jsonBody as any).data).toEqual([1, 2, 3]);
  });

  it('handles null data', () => {
    const response = successResponse(null);
    expect((response.jsonBody as any).data).toBeNull();
  });
});

describe('errorResponse', () => {
  it('wraps error in standard envelope', () => {
    const response = errorResponse('NOT_FOUND', 'Resource not found', 404);
    expect(response.status).toBe(404);
    expect((response.jsonBody as any).data).toBeNull();
    expect((response.jsonBody as any).error).toEqual({
      code: 'NOT_FOUND',
      message: 'Resource not found',
    });
  });

  it('defaults to status 400', () => {
    const response = errorResponse('BAD', 'Bad request');
    expect(response.status).toBe(400);
  });

  it('sets Content-Type header', () => {
    const response = errorResponse('ERR', 'msg');
    expect((response.headers as Record<string, string>)['Content-Type']).toBe('application/json');
  });

  it('includes request_id when provided', () => {
    const response = errorResponse('ERR', 'msg', 400, 'req-123');
    expect((response.jsonBody as any).error.request_id).toBe('req-123');
  });

  it('omits request_id when not provided', () => {
    const response = errorResponse('ERR', 'msg');
    expect((response.jsonBody as any).error.request_id).toBeUndefined();
  });
});
