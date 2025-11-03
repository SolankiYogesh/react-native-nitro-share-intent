import { useEffect } from 'react';
import type { NitroShareIntent, SharePayload } from './NitroShareIntent.nitro';
import { NitroModules } from 'react-native-nitro-modules';
const shareIntentModule =
  NitroModules.createHybridObject<NitroShareIntent>('NitroShareIntent');

export function useShareIntent(
  onShareReceived: (payload: SharePayload) => void
) {
  useEffect(() => {
    shareIntentModule.onIntentListener((payload) => {
      console.log('payload', payload);
      onShareReceived(payload);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

export const getInitialShare = () => {
  return new Promise<SharePayload | null>((resolve) => {
    shareIntentModule
      .getInitialShare()
      .then((payload) => {
        if (payload) {
          if (payload.text === 'text' && !payload.files && !payload.text) {
            return;
          }
          resolve(payload);
        }
      })
      .catch(() => {
        resolve(null);
      });
  });
};
