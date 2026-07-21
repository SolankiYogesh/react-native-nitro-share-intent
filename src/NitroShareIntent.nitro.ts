import { type HybridObject } from 'react-native-nitro-modules';

export type ShareType = 'text' | 'file' | 'multiple';

export type SharePayload = {
  type: ShareType;
  text?: string;
  files?: string[];
  extras?: Record<string, string>;
};

export interface NitroShareIntent extends HybridObject<{
  ios: 'swift';
  android: 'kotlin';
}> {
  /**
   * Resolves with the share payload that was pending when the app was
   * opened/launched, or `undefined` if there is none to report.
   *
   * NOTE: this is the low-level native bridge contract. The public
   * `getInitialShare()` helper exported from `useShareIntent.ts` normalizes
   * this value to `null` to match its documented
   * `Promise<SharePayload | null>` contract - treat this native method as an
   * internal implementation detail.
   *
   * Rejects if the native side failed to read/parse the pending share -
   * this is distinct from "nothing was shared", which resolves with
   * `undefined`.
   */
  getInitialShare(): Promise<SharePayload | undefined>;

  /**
   * Subscribes to incoming share intents. Multiple listeners may be
   * registered independently (e.g. from multiple mounted hook instances);
   * each call returns a unique listener id that can later be passed to
   * `removeListener` to unsubscribe.
   */
  onIntentListener(listener: (payload: SharePayload) => void): number;

  /**
   * Subscribes to native errors encountered while reading/parsing a share
   * (e.g. failing to copy a shared file to a readable location). Returns a
   * unique listener id that can later be passed to `removeListener`.
   */
  onErrorListener(listener: (message: string) => void): number;

  /**
   * Unsubscribes a listener previously registered via `onIntentListener` or
   * `onErrorListener`.
   */
  removeListener(listenerId: number): void;

  /**
   * Clears any pending/cached share intent so a subsequent
   * `getInitialShare()` call resolves with `undefined` until a new share
   * arrives.
   */
  clearShareIntent(): void;
}
