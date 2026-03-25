import * as appInsights from 'applicationinsights';

let isInitialized = false;

export function initTelemetry(): void {
  if (isInitialized) return;
  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  if (connectionString) {
    appInsights.setup(connectionString)
      .setAutoCollectRequests(true)
      .setAutoCollectPerformance(true)
      .setAutoCollectExceptions(true)
      .setAutoCollectDependencies(true)
      .start();
    isInitialized = true;
  } else {
    console.warn('APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled');
  }
}

// Auto-initialize on module load so HTTP handlers get telemetry
initTelemetry();

export function trackEvent(name: string, properties?: Record<string, string>): void {
  if (!isInitialized) return;
  appInsights.defaultClient?.trackEvent({ name, properties });
}

export function trackError(error: Error, properties?: Record<string, string>): void {
  if (!isInitialized) return;
  appInsights.defaultClient?.trackException({ exception: error, properties });
}
