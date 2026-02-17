export type Category = 'code' | 'data' | 'heap' | 'stack' | 'mapped' | 'shared' | 'system';

export const CATEGORIES: Category[] = [
  'code',
  'data',
  'system',
  'mapped',
  'shared',
  'stack',
  'heap',
];

export const CATEGORY_COLORS: Record<Category, string> = {
  code: '#3b82f6',
  data: '#22c55e',
  heap: '#f97316',
  stack: '#ef4444',
  mapped: '#a855f7',
  shared: '#06b6d4',
  system: '#6b7280',
};

export const CATEGORY_LABELS: Record<Category, string> = {
  code: 'Code',
  data: 'Data',
  heap: 'Heap',
  stack: 'Stack',
  mapped: 'Mapped',
  shared: 'Shared',
  system: 'System',
};

const EXACT: Record<string, Category> = {
  '__TEXT': 'code',
  '__LINKEDIT': 'code',
  '__DATA': 'data',
  '__DATA_CONST': 'data',
  '__DATA_DIRTY': 'data',
  'Stack': 'stack',
  'STACK GUARD': 'stack',
  'mapped file': 'mapped',
  'shared memory': 'shared',
};

const PREFIX_RULES: [string, Category][] = [
  ['MALLOC', 'heap'],
  ['__OBJC', 'data'],
  ['__AUTH', 'data'],
];

export function categoryForType(regionType: string): Category {
  const exact = EXACT[regionType];
  if (exact) {
    return exact;
  }

  for (const [prefix, category] of PREFIX_RULES) {
    if (regionType.startsWith(prefix)) {
      return category;
    }
  }

  return 'system';
}

export function colorForType(regionType: string): string {
  return CATEGORY_COLORS[categoryForType(regionType)];
}
