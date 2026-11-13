import { Card, CardContent, Typography } from '@mui/material';
import { Title, useTranslate } from 'react-admin';

export const Dashboard = () => {
  const translate = useTranslate();
  return (
    <Card sx={{ mt: 2 }}>
      <Title title="app.title" />
      <CardContent>
        <Typography variant="h5" component="h2" gutterBottom>
          {translate('app.dashboard.title')}
        </Typography>
        <Typography variant="body1">{translate('app.dashboard.description')}</Typography>
      </CardContent>
    </Card>
  );
};
