import { Alert, Button } from '@mui/material';
import { useTranslate } from 'react-admin';
import { useClientUpdate } from '../providers/clientUpdate';

export const ClientUpdateNotice = ({
  reload = () => {
    window.location.reload();
  },
}: {
  reload?: () => void;
}) => {
  const update = useClientUpdate();
  const translate = useTranslate();
  if (!update) return null;
  return (
    <Alert
      severity="warning"
      action={
        <Button color="inherit" onClick={reload}>
          {translate('app.clientUpdate.reload')}
        </Button>
      }
    >
      {translate('app.clientUpdate.message')}
      {update.minVersion &&
        ` ${translate('app.clientUpdate.minimum', { version: update.minVersion })}`}
    </Alert>
  );
};
