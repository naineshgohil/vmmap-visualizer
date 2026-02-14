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
    VmmapCollectorModule.create(665, 1000);
    VmmapCollectorModule.start();

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
