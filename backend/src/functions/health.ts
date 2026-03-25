import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { successResponse } from '../shared/utils/response';

async function health(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return successResponse({ status: 'healthy', timestamp: new Date().toISOString() });
}

app.http('health', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'health',
  handler: health,
});
