import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useIsAuthenticated } from '@azure/msal-react';
import { verifyAuth } from '../../api/endpoints/auth';

/**
 * Runs POST /api/auth/verify exactly once per authenticated session. The
 * backend uses this to upsert the user row and enforce the age gate. Failure
 * cases (403 AGE_VERIFICATION_FAILED) are handled by the axios response
 * interceptor in api/client.ts.
 */
export function useAuthVerify() {
  const isAuthenticated = useIsAuthenticated();

  const query = useQuery({
    queryKey: ['auth', 'verify'],
    queryFn: verifyAuth,
    enabled: isAuthenticated,
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
  });

  useEffect(() => {
    if (query.isError) {
      console.error('auth verify failed', query.error);
    }
  }, [query.isError, query.error]);

  return query;
}
