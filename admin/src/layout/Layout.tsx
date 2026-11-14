import { ClientUpdateNotice } from './ClientUpdateNotice';
import MonitorHeartIcon from '@mui/icons-material/MonitorHeart';
import type { ReactNode } from 'react';
import { Layout as RaLayout, Menu as RaMenu } from 'react-admin';

const Menu = () => (
  <RaMenu>
    <RaMenu.DashboardItem />
    <RaMenu.ResourceItems />
    <RaMenu.Item
      to="/api-status"
      primaryText="app.apiStatus.menu"
      leftIcon={<MonitorHeartIcon />}
    />
  </RaMenu>
);

export const Layout = ({ children }: { children: ReactNode }) => (
  <RaLayout menu={Menu}>
    <ClientUpdateNotice />
    {children}
  </RaLayout>
);
