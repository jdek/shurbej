import { createSignal } from "solid-js";
import type { LibraryType } from "./library";

export interface Tab {
  id: string;
  type: "library" | "pdf";
  label: string;
  itemKey?: string;
  fetchUrl?: string;
  /** Library the tab was opened from; PDFs need this so switching the sidebar
   * library doesn't invalidate an already-open PDF's download URL. */
  libraryType?: LibraryType;
  libraryId?: number;
}

let nextId = 1;

const [tabs, setTabs] = createSignal<Tab[]>([
  { id: "library", type: "library", label: "Library" },
]);

const [activeTab, setActiveTab] = createSignal("library");

export function openPdfTab(
  itemKey: string,
  title: string,
  fetchUrl: string,
  library?: { type: LibraryType; id: number },
) {
  const existing = tabs().find((t) => t.type === "pdf" && t.itemKey === itemKey);
  if (existing) {
    setActiveTab(existing.id);
    return;
  }
  const id = `tab-${nextId++}`;
  const tab: Tab = {
    id, type: "pdf", label: title, itemKey, fetchUrl,
    libraryType: library?.type,
    libraryId: library?.id,
  };
  setTabs([...tabs(), tab]);
  setActiveTab(id);
}

export function closeTab(id: string) {
  if (id === "library") return;
  const current = tabs();
  const idx = current.findIndex((t) => t.id === id);
  const next = current.filter((t) => t.id !== id);
  setTabs(next);
  if (activeTab() === id) {
    const newIdx = Math.min(idx, next.length - 1);
    setActiveTab(next[newIdx].id);
  }
}

export function switchTab(id: string) {
  setActiveTab(id);
}

export { tabs, activeTab };
