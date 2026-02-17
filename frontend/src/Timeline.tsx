import React, {useMemo} from 'react';
import {View, Text, StyleSheet} from 'react-native';
import Svg, {Line, Path} from 'react-native-svg';
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

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function niceNum(range: number, round: boolean): number {
  const exp = Math.floor(Math.log10(range));
  const frac = range / Math.pow(10, exp);
  let nice: number;
  if (round) {
    if (frac < 1.5) { nice = 1; }
    else if (frac < 3) { nice = 2; }
    else if (frac < 7) { nice = 5; }
    else { nice = 10; }
  } else {
    if (frac <= 1) { nice = 1; }
    else if (frac <= 2) { nice = 2; }
    else if (frac <= 5) { nice = 5; }
    else { nice = 10; }
  }
  return nice * Math.pow(10, exp);
}

function getTicks(min: number, max: number, count: number): number[] {
  const range = niceNum(max - min, false);
  const step = niceNum(range / (count - 1), true);
  const niceMin = Math.floor(min / step) * step;
  const niceMax = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let v = niceMin; v <= niceMax + step * 0.5; v += step) {
    ticks.push(v);
  }
  return ticks;
}

function buildLinePath(
  points: {x: number; y: number}[],
): string {
  if (points.length === 0) { return ''; }
  if (points.length === 1) { return `M${points[0].x},${points[0].y}`; }

  let d = `M${points[0].x},${points[0].y}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[Math.max(i - 1, 0)];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[Math.min(i + 2, points.length - 1)];

    const cp1x = p1.x + (p2.x - p0.x) / 6;
    const cp1y = p1.y + (p2.y - p0.y) / 6;
    const cp2x = p2.x - (p3.x - p1.x) / 6;
    const cp2y = p2.y - (p3.y - p1.y) / 6;

    d += ` C${cp1x},${cp1y} ${cp2x},${cp2y} ${p2.x},${p2.y}`;
  }
  return d;
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

  const yMax = useMemo(() => {
    let m = 0;
    for (const d of snapshotData) {
      for (const cat of CATEGORIES) {
        if (d[cat] > m) {
          m = d[cat];
        }
      }
    }
    return m || 1;
  }, [snapshotData]);

  if (snapshots.length === 0 || width === 0 || height === 0) {
    return null;
  }

  const svgHeight = height - PADDING_BOTTOM;
  const drawWidth = width - PADDING_LEFT - PADDING_RIGHT;
  const drawHeight = svgHeight - PADDING_TOP - PADDING_TOP;

  const xMin = 0;
  const xMax = Math.max(snapshotData.length - 1, 1);
  const scaleX = (v: number) =>
    lerp(PADDING_LEFT, PADDING_LEFT + drawWidth, (v - xMin) / (xMax - xMin));

  const yTicks = getTicks(0, yMax, 5);
  const yNiceMax = yTicks[yTicks.length - 1];
  const scaleY = (v: number) =>
    lerp(PADDING_TOP + drawHeight, PADDING_TOP, v / yNiceMax);

  const paths = CATEGORIES.map(cat => {
    const values = snapshotData.map(d => d[cat]);
    if (values.every(v => v === 0)) {
      return null;
    }
    const points = values.map((v, i) => ({x: scaleX(i), y: scaleY(v)}));
    const d = buildLinePath(points);
    if (!d) {
      return null;
    }
    return (
      <Path
        key={cat}
        d={d}
        stroke={CATEGORY_COLORS[cat]}
        strokeWidth={2}
        fill="none"
      />
    );
  });

  const gridLines = yTicks.map(tick => {
    const y = scaleY(tick);
    return (
      <Line
        key={tick}
        x1={PADDING_LEFT}
        y1={y}
        x2={PADDING_LEFT + drawWidth}
        y2={y}
        stroke="#333"
        strokeWidth={0.5}
      />
    );
  });

  return (
    <View style={{width, height}}>
      <Svg width={width} height={svgHeight} viewBox={`0 0 ${width} ${svgHeight}`}>
        {gridLines}
        {paths}
      </Svg>

      {yTicks.map(tick => {
        const y = scaleY(tick);
        return (
          <Text
            key={tick}
            style={[styles.yLabel, {top: y - 8, left: 0, width: PADDING_LEFT - 8}]}>
            {formatBytes(tick)}
          </Text>
        );
      })}

      <View style={styles.legend}>
        {[...CATEGORIES].reverse().map(cat => (
          <View key={cat} style={styles.legendItem}>
            <View
              style={[styles.legendSwatch, {backgroundColor: CATEGORY_COLORS[cat]}]}
            />
            <Text style={styles.legendText}>{CATEGORY_LABELS[cat]}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
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
