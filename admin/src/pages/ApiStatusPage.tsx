import { Alert, Button, Card, CardContent, CircularProgress, Stack } from '@mui/material';
import { useQuery } from '@tanstack/react-query';
import { Title, useTranslate } from 'react-admin';
import { config } from '../config';
import type { HttpClient } from '../providers/httpClient';

/** Calls `GET /health` to confirm the panel reaches the API. */
export const ApiStatusPage = ({ httpClient }: { httpClient: HttpClient }) => {
  const translate = useTranslate();
  const { isPending, isFetching, error, refetch } = useQuery({
    queryKey: ['api-health'],
    queryFn: ({ signal }) => httpClient(`${config.apiUrl}/health`, { signal }),
    retry: false,
  });

  return (
    <Card sx={{ mt: 2 }}>
      <Title title="app.apiStatus.title" />
      <CardContent>
        <Stack spacing={2} sx={{ alignItems: 'flex-start' }}>
          {isPending ? (
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
              <CircularProgress size={20} />
              <span>{translate('app.apiStatus.checking')}</span>
            </Stack>
          ) : error ? (
            <Alert severity="error">
              {translate('app.apiStatus.unavailable', { error: error.message })}
            </Alert>
          ) : (
            <Alert severity="success">{translate('app.apiStatus.ok')}</Alert>
          )}
          <Button
            variant="outlined"
            disabled={isFetching}
            onClick={() => {
              void refetch();
            }}
          >
            {translate('app.apiStatus.retry')}
          </Button>
        </Stack>
      </CardContent>
    </Card>
  );
};
