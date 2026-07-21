import type { SharePayload } from './NitroShareIntent.nitro';

type ShareListener = (payload: SharePayload) => void;
type ErrorListener = (message: string) => void;

/**
 * A lightweight, in-memory mock of the native `NitroShareIntent` module,
 * intended for Jest tests (or Storybook/simulators) so consumer apps can
 * exercise their share-handling code without a real device or the native
 * module being available.
 *
 * It intentionally mirrors the shape of the native module
 * (`onIntentListener`/`onErrorListener`/`removeListener`/`getInitialShare`/
 * `clearShareIntent`) so it can be used as a drop-in replacement when
 * mocking `react-native-nitro-share-intent` in tests, e.g.:
 *
 * ```ts
 * import { MockShareIntentModule } from 'react-native-nitro-share-intent/mock';
 *
 * const mockModule = new MockShareIntentModule();
 *
 * jest.mock('react-native-nitro-share-intent', () => {
 *   const actual = jest.requireActual('react-native-nitro-share-intent');
 *   return {
 *     ...actual,
 *     useShareIntent: (onShare, onError) => {
 *       // wire `mockModule` into a test-only hook implementation, or use
 *       // `mockModule.simulateShare(...)` directly against your own
 *       // listener/callback in a unit test.
 *     },
 *   };
 * });
 *
 * mockModule.simulateShare({ type: 'text', text: 'Hello from a test' });
 * ```
 */
export class MockShareIntentModule {
  private shareListeners = new Map<number, ShareListener>();
  private errorListeners = new Map<number, ErrorListener>();
  private nextListenerId = 0;
  private pendingShare: SharePayload | undefined;

  getInitialShare(): Promise<SharePayload | undefined> {
    return Promise.resolve(this.pendingShare);
  }

  onIntentListener(listener: ShareListener): number {
    const id = ++this.nextListenerId;
    this.shareListeners.set(id, listener);

    if (this.pendingShare) {
      listener(this.pendingShare);
    }

    return id;
  }

  onErrorListener(listener: ErrorListener): number {
    const id = ++this.nextListenerId;
    this.errorListeners.set(id, listener);
    return id;
  }

  removeListener(id: number): void {
    this.shareListeners.delete(id);
    this.errorListeners.delete(id);
  }

  clearShareIntent(): void {
    this.pendingShare = undefined;
  }

  /** Test helper: simulate an incoming share intent being delivered. */
  simulateShare(payload: SharePayload): void {
    this.pendingShare = payload;
    this.shareListeners.forEach((listener) => listener(payload));
  }

  /** Test helper: simulate a native error being reported. */
  simulateError(message: string): void {
    this.errorListeners.forEach((listener) => listener(message));
  }
}

export const createMockShareIntentModule = (): MockShareIntentModule =>
  new MockShareIntentModule();
