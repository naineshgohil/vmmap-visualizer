import { useEffect } from 'react';
import { NativeModules } from 'react-native';

const { VmmapCollectorModule } = NativeModules;

export interface Region {
  type: string;
  start: number;
  end: number;
  vsize: number;
  rsize: number;
}

export interface Snapshot {
  timestamp: number;
  regions: Region[];
}

export function useCollector() {
  useEffect(() => {
    (async () => {
      try {
        await VmmapCollectorModule.create(700, 1000);
        await VmmapCollectorModule.start();
      } catch (error) {
        console.log('Collector error', error);
      }
    })();

    return () => {
      VmmapCollectorModule.stop();
    };
  }, []);

  const getSnapshots = async (): Promise<Snapshot[]> => {
    const json = await VmmapCollectorModule.getSnapshots();
    return JSON.parse(json);
  };

  return { getSnapshots };
}
