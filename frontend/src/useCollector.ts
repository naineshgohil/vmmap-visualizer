import { useEffect, useState } from 'react';
import { NativeModules, NativeEventEmitter } from 'react-native';
import type { Snapshot } from './types';

const { VmmapCollectorModule } = NativeModules;
const emitter = new NativeEventEmitter(VmmapCollectorModule);

export function useCollector(pid: number | null, intervalMs: number) {
  const [snapshots, setSnapshots] = useState<Snapshot[]>([]);

  useEffect(() => {
    if (pid === null) {
      return;
    }

    setSnapshots([]);

    (async () => {
      try {
        await VmmapCollectorModule.create(pid, intervalMs);
        await VmmapCollectorModule.start();
      } catch (error) {
        console.log('[vmmap:frontend]: collector create/start error\n', error);
      }
    })();

    return () => {
      VmmapCollectorModule.stop();
    };
  }, [pid, intervalMs]);

  useEffect(() => {
    const { remove } = emitter.addListener(
      'onSnapshot',
      (snapshot: Snapshot) => {
        console.log('[vmmap:frontend]: onSnapshot\n', snapshot);
        setSnapshots(prev => [...prev, snapshot]);
      },
    );

    return () => remove();
  }, []);

  return snapshots;
}
