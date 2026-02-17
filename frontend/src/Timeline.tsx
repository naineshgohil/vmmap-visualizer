import React, {useMemo} from 'react';
import {View, Text, StyleSheet} from 'react-native';
import type {Snapshot} from './types';
import {
  CATEGORIES,
  CATEGORY_COLORS,
  CATEGORY_LABELS,
  categoryForType,
  type Category,
} from './regionColors';

interface Props {
  snapshots: Snapshot[];
  width: number;
  height: number;
}

const PADDING_LEFT = 64;
const PADDING_RIGHT = 16;
const PADDING_TOP = 16;
const PADDING_BOTTOM = 40;

function formatBytes(bytes: number): string {
  if (bytes >= 1e9) {
    return (bytes / 1e9).toFixed(1) + ' GB';
  }
  if (bytes >= 1e6) {
    return (bytes / 1e6).toFixed(0) + ' MB';
  }
  if (bytes >= 1e3) {
    return (bytes / 1e3).toFixed(0) + ' KB';
  }
  return bytes + ' B';
}

function niceTicks(max: number, count: number): number[] {
  if (max <= 0) {
    return [0];
  }
  const roughStep = max / count;
  const mag = Math.pow(10, Math.floor(Math.log10(roughStep)));
  const residual = roughStep / mag;
  let step: number;
  if (residual <= 1.5) {
    step = mag;
  } else if (residual <= 3) {
    step = 2 * mag;
  } else if (residual <= 7) {
    step = 5 * mag;
  } else {
    step = 10 * mag;
  }
  const ticks: number[] = [];
  for (let v = 0; v <= max; v += step) {
    ticks.push(v);
  }
  return ticks;
}

function Timeline({snapshots, width, height}: Props) {
  const snapshotData = useMemo(() => {
    return snapshots.map(snapshot => {
      const totals = {} as Record<Category, number>;
      for (const cat of CATEGORIES) {
        totals[cat] = 0;
      }
      for (const region of snapshot.regions) {
        totals[categoryForType(region.type)] += region.vsize;
      }
      return totals;
    });
  }, [snapshots]);

  const maxTotal = useMemo(() => {
    let max = 0;
    for (const d of snapshotData) {
      let total = 0;
      for (const cat of CATEGORIES) {
        total += d[cat];
      }
      if (total > max) {
        max = total;
      }
    }
    return max || 1;
  }, [snapshotData]);

  if (snapshots.length === 0 || width === 0 || height === 0) {
    return null;
  }

  const drawWidth = width - PADDING_LEFT - PADDING_RIGHT;
  const drawHeight = height - PADDING_TOP - PADDING_BOTTOM;
  const columnWidth = drawWidth / snapshots.length;
  const ticks = niceTicks(maxTotal, 4);
  const yMax = ticks[ticks.length - 1] || maxTotal;

  const bars: React.ReactElement[] = [];
  for (let i = 0; i < snapshotData.length; i++) {
    const data = snapshotData[i];
    const x = PADDING_LEFT + i * columnWidth;
    let yOffset = 0;

    for (const cat of CATEGORIES) {
      const bytes = data[cat];
      if (bytes <= 0) {
        continue;
      }
      const segmentHeight = (bytes / yMax) * drawHeight;
      const y = PADDING_TOP + drawHeight - yOffset - segmentHeight;
      yOffset += segmentHeight;

      bars.push(
        <View
          key={`${i}-${cat}`}
          style={{
            position: 'absolute',
            left: x,
            top: y,
            width: Math.max(columnWidth, 1),
            height: Math.max(segmentHeight, 0.5),
            backgroundColor: CATEGORY_COLORS[cat],
          }}
        />,
      );
    }
  }

  return (
    <View style={{width, height}}>
      {bars}

      {ticks.map(tick => {
        const y = PADDING_TOP + drawHeight - (tick / yMax) * drawHeight;
        return (
          <React.Fragment key={tick}>
            <View style={[styles.gridLine, {top: y, left: PADDING_LEFT, width: drawWidth}]} />
            <Text style={[styles.yLabel, {top: y - 8, left: 0, width: PADDING_LEFT - 8}]}>
              {formatBytes(tick)}
            </Text>
          </React.Fragment>
        );
      })}

      <View style={styles.legend}>
        {[...CATEGORIES].reverse().map(cat => (
          <View key={cat} style={styles.legendItem}>
            <View style={[styles.legendSwatch, {backgroundColor: CATEGORY_COLORS[cat]}]} />
            <Text style={styles.legendText}>{CATEGORY_LABELS[cat]}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  gridLine: {
    position: 'absolute',
    height: StyleSheet.hairlineWidth,
    backgroundColor: '#333',
  },
  yLabel: {
    position: 'absolute',
    color: '#888',
    fontSize: 10,
    textAlign: 'right',
  },
  legend: {
    position: 'absolute',
    bottom: 8,
    left: PADDING_LEFT,
    flexDirection: 'row',
    gap: 16,
  },
  legendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  legendSwatch: {
    width: 10,
    height: 10,
    borderRadius: 2,
  },
  legendText: {
    color: '#888',
    fontSize: 11,
  },
});

export default Timeline;
