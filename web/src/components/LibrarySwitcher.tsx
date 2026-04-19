import { For } from "solid-js";
import { useNavigate } from "@solidjs/router";
import {
  libraries,
  selectedLibrary,
  setSelectedLibrary,
  type Library,
} from "../lib/library";
import { invalidateAll } from "../lib/query-cache";
import { clearTags } from "../lib/tags";

function libKey(lib: Library) {
  return `${lib.type}:${lib.id}`;
}

function findLib(key: string): Library | undefined {
  return libraries().find((l) => libKey(l) === key);
}

export default function LibrarySwitcher() {
  const navigate = useNavigate();

  function onChange(e: Event) {
    const target = e.currentTarget as HTMLSelectElement;
    const next = findLib(target.value);
    if (!next) return;
    const prev = selectedLibrary();
    if (prev && libKey(prev) === libKey(next)) return;
    setSelectedLibrary(next);
    clearTags();
    invalidateAll();
    navigate("/");
  }

  return (
    <div class="px-3 pb-2">
      <select
        class="w-full bg-raised border border-border rounded px-2 py-1 text-sm text-white
               focus:outline-none focus:border-accent"
        value={selectedLibrary() ? libKey(selectedLibrary()!) : ""}
        onChange={onChange}
      >
        <For each={libraries()}>
          {(lib) => (
            <option value={libKey(lib)}>{lib.name}</option>
          )}
        </For>
      </select>
    </div>
  );
}
