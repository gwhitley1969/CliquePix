import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

async function health(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return {
    status: 200,
    jsonBody: { status: 'healthy', timestamp: new Date().toISOString() },
  };
}

app.http('health', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'health',
  handler: health,
});
