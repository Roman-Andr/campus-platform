import { Box, Button, Card, CardContent, Stack, Typography } from '@mui/material';
import { LocalesMenuButton, useLogin, useNotify, useTranslate } from 'react-admin';

/** Placeholder login page; real sign-in comes with issue #97. */
export const LoginPage = () => {
  const translate = useTranslate();
  const login = useLogin();
  const notify = useNotify();

  const handleContinue = () => {
    login({}).catch((error: unknown) => {
      notify(error instanceof Error ? error.message : 'ra.auth.sign_in_error', { type: 'error' });
    });
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        bgcolor: 'background.default',
      }}
    >
      <Card sx={{ width: 400, maxWidth: '90vw' }}>
        <CardContent>
          <Stack spacing={2}>
            <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between' }}>
              <Typography variant="h5" component="h1">
                {translate('app.login.title')}
              </Typography>
              <LocalesMenuButton />
            </Stack>
            <Typography variant="subtitle1">{translate('app.title')}</Typography>
            <Typography variant="body2" color="text.secondary">
              {translate('app.login.stub')}
            </Typography>
            <Button variant="contained" onClick={handleContinue}>
              {translate('app.login.continue')}
            </Button>
          </Stack>
        </CardContent>
      </Card>
    </Box>
  );
};
