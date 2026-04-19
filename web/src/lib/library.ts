import { createSignal } from "solid-js";
import { userId } from "./auth";

export type LibraryType = "user" | "group";

export interface Library {
  type: LibraryType;
  id: number;
  name: string;
}

const STORAGE_KEY = "shurbej_selected_library";

function readStored(): Library | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Library;
    if (parsed && (parsed.type === "user" || parsed.type === "group")
        && typeof parsed.id === "number") {
      return parsed;
    }
  } catch {
    /* fall through */
  }
  return null;
}

const [libraries, setLibrariesRaw] = createSignal<Library[]>([]);
const [selectedLibrary, setSelectedLibraryRaw] =
  createSignal<Library | null>(readStored());

export function setLibraries(libs: Library[]) {
  setLibrariesRaw(libs);
  // If the currently selected library no longer exists, reset to the user's own.
  const sel = selectedLibrary();
  if (sel && !libs.find((l) => l.type === sel.type && l.id === sel.id)) {
    const self = libs.find((l) => l.type === "user");
    if (self) setSelectedLibrary(self);
  } else if (!sel) {
    const self = libs.find((l) => l.type === "user");
    if (self) setSelectedLibrary(self);
  }
}

export function setSelectedLibrary(lib: Library | null) {
  if (lib) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(lib));
  } else {
    localStorage.removeItem(STORAGE_KEY);
  }
  setSelectedLibraryRaw(lib);
}

/** The library used by library-scoped API calls. Falls back to the
 * authenticated user's library while group listing hasn't landed yet. */
export function currentLibrary(): Library {
  const sel = selectedLibrary();
  if (sel) return sel;
  const uid = userId();
  return { type: "user", id: uid ?? 0, name: "My Library" };
}

export function clearLibraries() {
  setLibrariesRaw([]);
  setSelectedLibrary(null);
}

export { libraries, selectedLibrary };
