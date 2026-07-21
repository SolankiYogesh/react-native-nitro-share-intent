// react-native-web / web bundler target stub.
//
// `NitroModules.createHybridObject` has no native counterpart on web, so
// importing the default `./index.tsx` entry point there would throw at
// module-init time. Bundlers that resolve web-specific files (Metro with
// the `web` platform, Webpack/`react-native-web`, etc.) will pick this file
// over `index.tsx` automatically, giving consumers no-op fallbacks instead
// of a crash.
import { useEffect } from 'react';
import type { SharePayload } from './NitroShareIntent.nitro';

export type { ShareType, SharePayload } from './NitroShareIntent.nitro';
export { ShareIntentUtils } from './ShareIntentUtils';

export function useShareIntent(
  _onShareReceived: (payload: SharePayload) => void,
  _onError?: (message: string) => void
): void {
  useEffect(() => {
    // No-op on web: there is no native share intent to listen for.
  }, []);
}

export const getInitialShare = async (): Promise<SharePayload | null> => {
  return null;
};

export const clearShareIntent = (): void => {
  // No-op on web.
};
