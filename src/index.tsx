import { NitroModules } from 'react-native-nitro-modules';
import type { NitroShareIntent } from './NitroShareIntent.nitro';

const NitroShareIntentHybridObject =
  NitroModules.createHybridObject<NitroShareIntent>('NitroShareIntent');

export function multiply(a: number, b: number): number {
  return NitroShareIntentHybridObject.multiply(a, b);
}
