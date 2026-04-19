import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useIsAuthenticated, useMsal } from '@azure/msal-react';
import { AxiosError } from 'axios';
import { verifyAuth } from '../../api/endpoints/auth';

/**
 * Runs POST /api/auth/verify exactly once per authenticated session. The
 * backend uses this to upsert the user row and enforce the age gate. Failure
 * cases (403 AGE_VERIFICATION_FAILED) are handled by the axios response
 * interceptor in api/client.ts.
 *
 * If verify fails with 401 the session is unrecoverable (the Bearer token is
 * missing, wrong, or expired) — we force logoutRedirect so the user gets a
 * clean re-authentication instead of a broken-but-rendered app shell.
 */
export function useAuthVerify() {
  const isAuthenticated = useIsAuthenticated();
  const { instance } = useMsal();

  const query = useQuery({
    queryKey: ['auth', 'verify'],
    queryFn: verifyAuth,
    enabled: isAuthenticated,
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
  });

  useEffect(() => {
    if (!query.isError) return;
    console.error('auth verify failed', query.error);
    const status =
      query.error instanceof AxiosError ? query.error.response?.status : undefined;
    if (status === 401) {
      instance
        .logoutRedirect({ postLogoutRedirectUri: '/login' })
        .catch((err) => console.error('logoutRedirect after 401 failed', err));
    }
  }, [query.isError, query.error, instance]);

  return query;
}
