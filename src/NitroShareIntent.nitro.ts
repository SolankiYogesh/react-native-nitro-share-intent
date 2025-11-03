import { type HybridObject } from 'react-native-nitro-modules';

export type ShareType = 'text' | 'file' | 'multiple';

export type SharePayload = {
  type: ShareType;
  text?: string;
  files?: string[];
  extras?: Record<string, string>;
};

export interface NitroShareIntent
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  getInitialShare(): Promise<SharePayload | null>;
  onIntentListener(listener: (payload: SharePayload) => void): number;
}
