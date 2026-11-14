import { useSyncExternalStore } from 'react';

interface Update {
  minVersion: string | null;
}
let update: Update | null = null;
const listeners = new Set<() => void>();

export const reportClientUpdate = (minVersion: string | null) => {
  update = { minVersion };
  listeners.forEach((listener) => {
    listener();
  });
};

export const useClientUpdate = () =>
  useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    () => update,
  );
