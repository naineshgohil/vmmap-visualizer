import React, {useCallback, useState} from 'react';
import {
  LayoutChangeEvent,
  StyleSheet,
  View,
  Text,
  TextInput,
  Pressable,
} from 'react-native';
import {useCollector} from './useCollector';
import Timeline from './Timeline';

const INTERVAL_MS = 1000;

function App() {
  const [pidInput, setPidInput] = useState('');
  const [activePid, setActivePid] = useState<number | null>(null);
  const snapshots = useCollector(activePid, INTERVAL_MS);
  const [layout, setLayout] = useState({width: 0, height: 0});

  const onLayout = useCallback((e: LayoutChangeEvent) => {
    const {width, height} = e.nativeEvent.layout;
    setLayout({width, height});
  }, []);

  const handleSubmit = () => {
    const parsed = parseInt(pidInput, 10);
    if (!isNaN(parsed) && parsed > 0) {
      setActivePid(parsed);
    }
  };

  if (activePid === null) {
    return (
      <View style={styles.container}>
        <View style={styles.inputContainer}>
          <Text style={styles.title}>vmmap Visualizer</Text>
          <Text style={styles.label}>Process ID</Text>
          <TextInput
            style={styles.input}
            value={pidInput}
            onChangeText={setPidInput}
            onSubmitEditing={handleSubmit}
            placeholder="e.g. 12345"
            placeholderTextColor="#555"
            keyboardType="number-pad"
            autoFocus
          />
          <Pressable
            style={({pressed}) => [
              styles.button,
              pressed && styles.buttonPressed,
            ]}
            onPress={handleSubmit}>
            <Text style={styles.buttonText}>Start</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container} onLayout={onLayout}>
      <Timeline
        snapshots={snapshots}
        width={layout.width}
        height={layout.height}
      />
      <Text style={styles.debug}>
        {snapshots.length} snapshots | {layout.width}x{layout.height}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a2e',
  },
  inputContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    color: '#e0e0e0',
    fontSize: 24,
    fontWeight: '600',
    marginBottom: 32,
  },
  label: {
    color: '#888',
    fontSize: 14,
    marginBottom: 8,
  },
  input: {
    backgroundColor: '#16213e',
    color: '#e0e0e0',
    fontSize: 18,
    borderWidth: 1,
    borderColor: '#333',
    borderRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 10,
    width: 200,
    textAlign: 'center',
    marginBottom: 16,
  },
  button: {
    backgroundColor: '#3b82f6',
    borderRadius: 6,
    paddingHorizontal: 32,
    paddingVertical: 10,
  },
  buttonPressed: {
    opacity: 0.7,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  debug: {
    position: 'absolute',
    bottom: 8,
    right: 8,
    color: '#666',
    fontSize: 12,
  },
});

export default App;
