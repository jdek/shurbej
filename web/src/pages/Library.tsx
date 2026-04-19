import { createSignal, createMemo, Show, For } from "solid-js";
import { useSearchParams } from "@solidjs/router";
import { getTopItems, type ListParams, type ZoteroItem } from "../api/items";
import ItemTable from "../components/ItemTable";
import CreateItemModal from "../components/CreateItemModal";
import { selectedTags, clearTags, tagColors } from "../lib/tags";
import { selectedLibrary } from "../lib/library";
import { createCachedResource } from "../lib/query-cache";

const PAGE_SIZE = 50;

export default function Library() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [showCreate, setShowCreate] = createSignal(false);
  const [query, setQuery] = createSignal((searchParams.q as string) || "");

  const sort = () => (searchParams.sort as string) || "dateModified";
  const direction = () => ((searchParams.direction as string) || "desc") as "asc" | "desc";

  const cacheKey = () => {
    const lib = selectedLibrary();
    const libTag = lib ? `${lib.type}:${lib.id}` : "user:0";
    const p: ListParams = {
      limit: PAGE_SIZE,
      start: parseInt((searchParams.start as string) || "0", 10),
      sort: sort(),
      direction: direction(),
      q: searchParams.q as string | undefined,
      tag: selectedTags().length === 1 ? selectedTags()[0] : undefined,
    };
    return `items-top:${libTag}:${JSON.stringify(p)}`;
  };

  const [result, { refetch, loading }] = createCachedResource(
    cacheKey,
    (key) => {
      // Key format: items-top:<libTag>:<json params>
      const tail = key.slice(key.indexOf(":", "items-top:".length) + 1);
      const p = JSON.parse(tail);
      return getTopItems(p);
    },
  );

  const filteredItems = createMemo((): ZoteroItem[] => {
    const items = result()?.items || [];
    const tags = selectedTags();
    if (tags.length <= 1) return items;
    return items.filter((item) => {
      const itemTags = (item.data.tags || []).map((t) => t.tag);
      return tags.every((t) => itemTags.includes(t));
    });
  });

  function search(e: Event) {
    e.preventDefault();
    setSearchParams({ q: query() || undefined, start: undefined });
  }

  function handleSort(field: string, dir: "asc" | "desc") {
    setSearchParams({ sort: field, direction: dir, start: undefined });
  }

  const page = () => Math.floor(parseInt((searchParams.start as string) || "0", 10) / PAGE_SIZE);
  const totalResults = () => selectedTags().length > 1 ? filteredItems().length : (result()?.totalResults || 0);
  const totalPages = () => Math.ceil(totalResults() / PAGE_SIZE);

  return (
    <>
      <form class="flex gap-2 mb-4" onSubmit={search}>
        <input
          type="text"
          placeholder="Search items..."
          value={query()}
          onInput={(e) => setQuery(e.currentTarget.value)}
          class="flex-1 min-w-[200px] bg-bg border border-border rounded-md px-3 py-1.5 text-sm outline-none focus:border-accent"
        />
        <button type="submit" class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface">Search</button>
        <button type="button" class="px-3 py-1.5 text-sm rounded-md bg-accent text-bg font-medium hover:bg-accent-hover" onClick={() => setShowCreate(true)}>
          + New Item
        </button>
      </form>

      <Show when={selectedTags().length > 0}>
        <div class="mb-3 text-sm text-dim flex items-center gap-2 flex-wrap">
          <span>Tags:</span>
          <For each={selectedTags()}>
            {(tag) => {
              const color = () => tagColors()[tag];
              return (
                <span
                  class="text-xs px-2 py-0.5 rounded-full border"
                  style={color()
                    ? { "border-color": color()!, color: color() }
                    : { "border-color": "var(--color-border)" }
                  }
                >
                  {tag}
                </span>
              );
            }}
          </For>
          <button class="text-xs px-2 py-0.5 border border-border rounded hover:bg-surface" onClick={clearTags}>Clear</button>
        </div>
      </Show>

      <Show when={loading() && !result()}>
        <div class="text-center py-8 text-dim">Loading...</div>
      </Show>

      <Show when={result()}>
        <ItemTable
          items={filteredItems()}
          sort={sort()}
          direction={direction()}
          onSort={handleSort}
        />

        <Show when={totalPages() > 1}>
          <div class="flex items-center gap-2 mt-4 text-sm text-dim">
            <button
              class="px-2 py-1 text-xs border border-border rounded hover:bg-surface disabled:opacity-50"
              disabled={page() === 0}
              onClick={() => setSearchParams({ start: String((page() - 1) * PAGE_SIZE) })}
            >
              Prev
            </button>
            <span>Page {page() + 1} of {totalPages()} ({totalResults()} items)</span>
            <button
              class="px-2 py-1 text-xs border border-border rounded hover:bg-surface disabled:opacity-50"
              disabled={page() + 1 >= totalPages()}
              onClick={() => setSearchParams({ start: String((page() + 1) * PAGE_SIZE) })}
            >
              Next
            </button>
          </div>
        </Show>
      </Show>

      <Show when={showCreate()}>
        <CreateItemModal onClose={() => setShowCreate(false)} onCreated={refetch} />
      </Show>
    </>
  );
}
