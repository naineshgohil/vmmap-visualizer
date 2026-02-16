import { useEffect } from 'react';
import { NativeModules, NativeEventEmitter } from 'react-native';

const { VmmapCollectorModule } = NativeModules;
const emitter = new NativeEventEmitter(VmmapCollectorModule);

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
        await VmmapCollectorModule.create(25038, 1000);
        await VmmapCollectorModule.start();
      } catch (error) {
        console.log('Collector error', error);
      }
    })();

    return () => {
      VmmapCollectorModule.stop();
    };
  }, []);

  useEffect(() => {
    const { remove } = emitter.addListener('onSnapshot', snapshot => {
      console.log('App: snapshot', snapshot);
    });

    return () => remove();
  }, []);
}
