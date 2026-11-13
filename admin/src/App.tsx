import { Admin, CustomRoutes } from 'react-admin';
import { Route } from 'react-router-dom';
import { i18nProvider } from './i18n';
import { Layout } from './layout/Layout';
import { ApiStatusPage } from './pages/ApiStatusPage';
import { Dashboard } from './pages/Dashboard';
import { LoginPage } from './pages/LoginPage';
import { authProvider, dataProvider, httpClient } from './providers';

export const App = () => (
  <Admin
    title="app.title"
    dataProvider={dataProvider}
    authProvider={authProvider}
    i18nProvider={i18nProvider}
    loginPage={LoginPage}
    dashboard={Dashboard}
    layout={Layout}
    requireAuth
  >
    <CustomRoutes>
      <Route path="/api-status" element={<ApiStatusPage httpClient={httpClient} />} />
    </CustomRoutes>
  </Admin>
);
