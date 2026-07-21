import { useEffect } from 'react';
import type { NitroShareIntent, SharePayload } from './NitroShareIntent.nitro';
import { NitroModules } from 'react-native-nitro-modules';
const shareIntentModule =
  NitroModules.createHybridObject<NitroShareIntent>('NitroShareIntent');

export function useShareIntent(
  onShareReceived: (payload: SharePayload) => void,
  onError?: (message: string) => void
) {
  useEffect(() => {
    const listenerId = shareIntentModule.onIntentListener((payload) => {
      onShareReceived(payload);
    });

    const errorListenerId = onError
      ? shareIntentModule.onErrorListener(onError)
      : undefined;

    return () => {
      shareIntentModule.removeListener(listenerId);
      if (errorListenerId !== undefined) {
        shareIntentModule.removeListener(errorListenerId);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

export const getInitialShare = (): Promise<SharePayload | null> => {
  return new Promise<SharePayload | null>((resolve, reject) => {
    shareIntentModule
      .getInitialShare()
      .then((payload) => {
        if (!payload) {
          // Nothing was shared - always resolve so callers awaiting this
          // promise don't hang forever.
          resolve(null);
          return;
        }

        if (payload.type === 'text' && !payload.files && !payload.text) {
          // Empty/invalid text share - treat the same as "nothing shared".
          resolve(null);
          return;
        }

        resolve(payload);
      })
      .catch((error) => {
        // The native side failed to read/parse the pending share - this is
        // distinct from "nothing was shared" above (which resolves with
        // `null`), so reject instead of silently swallowing the error.
        reject(error instanceof Error ? error : new Error(String(error)));
      });
  });
};

export const clearShareIntent = (): void => {
  shareIntentModule.clearShareIntent();
};
