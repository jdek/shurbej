import { createSignal } from "solid-js";

export interface ColumnDef {
  id: string;
  label: string;
  sortKey: string | null;
  defaultWidth: number;
  minWidth: number;
}

export const ALL_COLUMNS: ColumnDef[] = [
  { id: "title", label: "Title", sortKey: "title", defaultWidth: 400, minWidth: 100 },
  { id: "creator", label: "Creator", sortKey: "creator", defaultWidth: 180, minWidth: 60 },
  { id: "itemType", label: "Type", sortKey: "itemType", defaultWidth: 100, minWidth: 50 },
  { id: "dateModified", label: "Modified", sortKey: "dateModified", defaultWidth: 100, minWidth: 50 },
  { id: "dateAdded", label: "Added", sortKey: "dateAdded", defaultWidth: 100, minWidth: 50 },
  { id: "year", label: "Year", sortKey: null, defaultWidth: 60, minWidth: 40 },
  { id: "publisher", label: "Publisher", sortKey: "publisher", defaultWidth: 140, minWidth: 60 },
  { id: "publicationTitle", label: "Publication", sortKey: "publicationTitle", defaultWidth: 160, minWidth: 60 },
  { id: "tags", label: "Tags", sortKey: null, defaultWidth: 160, minWidth: 60 },
  { id: "attachments", label: "Attachments", sortKey: null, defaultWidth: 50, minWidth: 40 },
];

const COLUMN_DEF_MAP = new Map(ALL_COLUMNS.map((c) => [c.id, c]));
export function getColumnDef(id: string): ColumnDef {
  return COLUMN_DEF_MAP.get(id)!;
}

export interface ColumnState {
  id: string;
  width: number;
}

const STORAGE_KEY = "shurbey_columns_v3";
const stored = localStorage.getItem(STORAGE_KEY);

const defaults: ColumnState[] = [
  { id: "title", width: 400 },
  { id: "creator", width: 180 },
  { id: "dateModified", width: 100 },
];

const [columns, setColumnsRaw] = createSignal<ColumnState[]>(
  stored ? JSON.parse(stored) : defaults
);

function persist(cols: ColumnState[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(cols));
  setColumnsRaw(cols);
}

export function setColumns(cols: ColumnState[]) {
  persist(cols);
}

export function addColumn(id: string) {
  const current = columns();
  if (current.some((c) => c.id === id)) return;
  const def = getColumnDef(id);
  if (!def) return;
  persist([...current, { id, width: def.defaultWidth }]);
}

export function removeColumn(id: string) {
  if (id === "title") return; // title is always visible
  const current = columns();
  if (current.length <= 1) return;
  persist(current.filter((c) => c.id !== id));
}

export function reorderColumn(fromIdx: number, toIdx: number) {
  const current = [...columns()];
  const [moved] = current.splice(fromIdx, 1);
  current.splice(toIdx, 0, moved);
  persist(current);
}

/** Resize the divider between col[idx] and col[idx+1] by delta pixels. */
export function resizeDivider(idx: number, delta: number) {
  const current = [...columns()];
  if (idx < 0 || idx + 1 >= current.length) return;
  const left = current[idx];
  const right = current[idx + 1];
  const leftDef = getColumnDef(left.id);
  const rightDef = getColumnDef(right.id);
  const minL = leftDef?.minWidth ?? 40;
  const minR = rightDef?.minWidth ?? 40;

  // clamp delta so neither column goes below minimum
  const clampedDelta = Math.max(minL - left.width, Math.min(right.width - minR, delta));
  current[idx] = { ...left, width: left.width + clampedDelta };
  current[idx + 1] = { ...right, width: right.width - clampedDelta };
  persist(current);
}

export { columns };
