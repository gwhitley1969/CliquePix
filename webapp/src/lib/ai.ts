import { ApplicationInsights } from '@microsoft/applicationinsights-web';

let appInsights: ApplicationInsights | null = null;

export function initAppInsights(): void {
  const connectionString = import.meta.env.VITE_APPLICATION_INSIGHTS_CONNECTION_STRING;
  if (!connectionString) return;

  appInsights = new ApplicationInsights({
    config: {
      connectionString,
      enableAutoRouteTracking: true,
      disableFetchTracking: false,
      enableCorsCorrelation: false,
    },
  });
  appInsights.loadAppInsights();
  appInsights.trackPageView();
}

export function trackEvent(name: string, properties?: Record<string, unknown>): void {
  if (!appInsights) return;
  appInsights.trackEvent({ name }, properties);
}

export function trackError(error: Error, properties?: Record<string, unknown>): void {
  if (!appInsights) return;
  appInsights.trackException({ exception: error }, properties);
}
