// @ts-ignore — @types/rox-node is v5, runtime is v6
import Rox from 'rox-node';
import { featureFlags, configFlags, headerTheme } from './flags.ts';

const GLOBAL_KEY = '__fmRox__';

declare global {
  var __fmRox__: typeof Rox | undefined;
}

export async function initFM(): Promise<void> {
  const key = process.env.FM_KEY || process.env.NEXT_PUBLIC_FM_KEY;
  if (!key) {
    console.log('[FM] No FM_KEY set — flags will use defaults');
    return;
  }

  if (globalThis[GLOBAL_KEY]) {
    console.log('[FM] Already initialised — skipping');
    return;
  }

  Rox.register('recall', { ...featureFlags, ...configFlags, headerTheme });

  try {
    await Rox.setup(key);
    globalThis[GLOBAL_KEY] = Rox;
    console.log('[FM] SDK initialized successfully');
  } catch (err) {
    console.error('[FM] SDK setup failed:', err);
  }
}

export function getFmRox(): typeof Rox | undefined {
  return globalThis[GLOBAL_KEY];
}

function companySizeBucket(employeeCount: number): string {
  if (employeeCount >= 500) return 'enterprise';
  if (employeeCount >= 100) return 'mid-market';
  return 'small';
}

export function setFmCustomProperties(props: {
  companyName?: string;
  companyId?: string;
  employeeCount?: number;
  naicsCode?: string;
  state?: string;
  userId?: string;
  email?: string;
  supplyChainRole?: string;
  productCategory?: string;
  isLoggedIn?: boolean;
}): void {
  if (props.companyName) Rox.setCustomStringProperty('company', props.companyName);
  if (props.companyId) Rox.setCustomStringProperty('companyId', props.companyId);
  if (props.employeeCount != null) Rox.setCustomStringProperty('companySize', companySizeBucket(props.employeeCount));
  if (props.naicsCode) Rox.setCustomStringProperty('naicsCode', props.naicsCode);
  if (props.productCategory) Rox.setCustomStringProperty('productCategory', props.productCategory);
  if (props.state) Rox.setCustomStringProperty('state', props.state);
  if (props.userId) Rox.setCustomStringProperty('userId', props.userId);
  if (props.email) Rox.setCustomStringProperty('email', props.email);
  if (props.supplyChainRole) Rox.setCustomStringProperty('supplyChainRole', props.supplyChainRole);
  if (props.isLoggedIn != null) Rox.setCustomBooleanProperty('isLoggedIn', props.isLoggedIn);
}
