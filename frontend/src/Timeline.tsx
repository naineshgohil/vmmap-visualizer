import React, {useMemo} from 'react';
import {View, Text, StyleSheet} from 'react-native';
import Svg, {Rect, Line} from 'react-native-svg';
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

interface TrackedRegion {
  key: string;
  type: string;
  start: number;
  end: number;
  vsize: number;
  category: Category;
  firstSnapshot: number;
  lastSnapshot: number;
}

const PADDING_LEFT = 72;
const PADDING_RIGHT = 16;
const PADDING_TOP = 16;
const PADDING_BOTTOM = 40;
const MIN_PX_HEIGHT = 1;

function formatAddr(addr: number): string {
  const hex = addr.toString(16).toUpperCase();
  if (hex.length > 8) {
    return '0x' + hex.slice(0, 4) + '..';
  }
  return '0x' + hex;
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function Timeline({snapshots, width, height}: Props) {
  const tracked = useMemo(() => {
    const map = new Map<string, TrackedRegion>();
    for (let i = 0; i < snapshots.length; i++) {
      for (const region of snapshots[i].regions) {
        const key = `${region.type}|${region.start}|${region.end}`;
        const existing = map.get(key);
        if (existing) {
          existing.lastSnapshot = i;
        } else {
          map.set(key, {
            key,
            type: region.type,
            start: region.start,
            end: region.end,
            vsize: region.vsize,
            category: categoryForType(region.type),
            firstSnapshot: i,
            lastSnapshot: i,
          });
        }
      }
    }
    const regions = Array.from(map.values());
    regions.sort((a, b) => a.start - b.start || a.end - b.end);
    return regions;
  }, [snapshots]);

  if (snapshots.length === 0 || width === 0 || height === 0) {
    return null;
  }

  const svgHeight = height - PADDING_BOTTOM;
  const drawWidth = width - PADDING_LEFT - PADDING_RIGHT;
  const drawHeight = svgHeight - PADDING_TOP - PADDING_TOP;
  const snapshotCount = snapshots.length;
  const columnWidth = drawWidth / Math.max(snapshotCount, 1);

  const scaleX = (i: number) =>
    lerp(PADDING_LEFT, PADDING_LEFT + drawWidth, i / Math.max(snapshotCount - 1, 1));

  const totalVsize = tracked.reduce((sum, r) => sum + r.vsize, 0);
  if (totalVsize === 0 || tracked.length === 0) {
    return null;
  }

  const pxPerByte = drawHeight / totalVsize;
  const rawHeights = tracked.map(r => Math.max(r.vsize * pxPerByte, MIN_PX_HEIGHT));
  const totalRaw = rawHeights.reduce((s, h) => s + h, 0);
  const scale = drawHeight / totalRaw;

  const yPositions: number[] = [];
  const heights: number[] = [];
  let yOffset = PADDING_TOP;
  for (let i = 0; i < tracked.length; i++) {
    yPositions.push(yOffset);
    const h = rawHeights[i] * scale;
    heights.push(h);
    yOffset += h;
  }

  const rects = tracked.map((r, i) => {
    const x = scaleX(r.firstSnapshot);
    const w = scaleX(r.lastSnapshot) - x + columnWidth;
    return (
      <Rect
        key={r.key}
        x={x}
        y={yPositions[i]}
        width={Math.max(w, 1)}
        height={Math.max(heights[i], 0.5)}
        fill={CATEGORY_COLORS[r.category]}
        opacity={0.8}
      />
    );
  });

  const categoryBoundaries: {y: number; addr: number; category: Category}[] = [];
  let lastCategory: Category | null = null;
  for (let i = 0; i < tracked.length; i++) {
    if (tracked[i].category !== lastCategory) {
      categoryBoundaries.push({
        y: yPositions[i],
        addr: tracked[i].start,
        category: tracked[i].category,
      });
      lastCategory = tracked[i].category;
    }
  }

  const boundaryLines = categoryBoundaries.map((b, i) => (
    <Line
      key={i}
      x1={PADDING_LEFT}
      y1={b.y}
      x2={PADDING_LEFT + drawWidth}
      y2={b.y}
      stroke="#444"
      strokeWidth={0.5}
    />
  ));

  return (
    <View style={{width, height}}>
      <Svg width={width} height={svgHeight} viewBox={`0 0 ${width} ${svgHeight}`}>
        {boundaryLines}
        {rects}
      </Svg>

      {categoryBoundaries.map((b, i) => (
        <Text
          key={i}
          style={[styles.yLabel, {top: b.y - 6, left: 0, width: PADDING_LEFT - 8}]}>
          {formatAddr(b.addr)}
        </Text>
      ))}

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
    fontSize: 9,
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
