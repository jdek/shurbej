import { createSignal, Show } from "solid-js";
import { useParams, useSearchParams } from "@solidjs/router";
import { api, libPath } from "../api/client";
import { getCollection } from "../api/collections";
import type { ZoteroItem } from "../api/items";
import ItemTable from "../components/ItemTable";
import CreateItemModal from "../components/CreateItemModal";
import { createCachedResource } from "../lib/query-cache";

const PAGE_SIZE = 50;

export default function CollectionView() {
  const routeParams = useParams<{ key: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const [showCreate, setShowCreate] = createSignal(false);

  const sort = () => (searchParams.sort as string) || "dateModified";
  const direction = () => ((searchParams.direction as string) || "desc") as "asc" | "desc";

  const [collection] = createCachedResource(
    () => `collection:${routeParams.key}`,
    () => getCollection(routeParams.key),
  );

  const itemsCacheKey = () => {
    const start = parseInt((searchParams.start as string) || "0", 10);
    return `coll-items:${routeParams.key}:${start}:${sort()}:${direction()}`;
  };

  const [result, { refetch, loading }] = createCachedResource(
    itemsCacheKey,
    async () => {
      const start = parseInt((searchParams.start as string) || "0", 10);
      const qs = `?limit=${PAGE_SIZE}&start=${start}&sort=${sort()}&direction=${direction()}`;
      const { data, headers } = await api<ZoteroItem[]>(
        libPath(`/collections/${routeParams.key}/items/top${qs}`)
      );
      return {
        items: data,
        totalResults: parseInt(headers.get("Total-Results") || "0", 10),
      };
    },
  );

  function handleSort(field: string, dir: "asc" | "desc") {
    setSearchParams({ sort: field, direction: dir, start: undefined });
  }

  const page = () => Math.floor(parseInt((searchParams.start as string) || "0", 10) / PAGE_SIZE);
  const totalPages = () => Math.ceil((result()?.totalResults || 0) / PAGE_SIZE);

  return (
    <>
      <Show when={collection()}>
        <div class="flex items-center gap-3 mb-4">
          <h2 class="text-lg font-semibold">{collection()!.data.name}</h2>
          <button
            class="px-3 py-1 text-sm rounded-md bg-accent text-bg font-medium hover:bg-accent-hover"
            onClick={() => setShowCreate(true)}
          >
            + New Item
          </button>
        </div>
      </Show>

      <Show when={loading() && !result()}>
        <div class="text-center py-8 text-dim">Loading...</div>
      </Show>

      <Show when={result()}>
        <ItemTable
          items={result()!.items}
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
            <span>Page {page() + 1} of {totalPages()}</span>
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
