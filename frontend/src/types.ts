export interface Region {
  type: string;
  start: number;
  end: number;
  vsize: number;
  rsize: number;
}

export interface Snapshot {
  timestamp_ms: number;
  regions: Region[];
}
