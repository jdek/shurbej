import { createResource, Show } from "solid-js";
import { useSearchParams } from "@solidjs/router";
import { getTrashItems } from "../api/items";
import ItemTable from "../components/ItemTable";
import { selectedLibrary } from "../lib/library";

const PAGE_SIZE = 50;

export default function Trash() {
  const [searchParams, setSearchParams] = useSearchParams();

  const sort = () => (searchParams.sort as string) || "dateModified";
  const direction = () => ((searchParams.direction as string) || "desc") as "asc" | "desc";

  const params = () => {
    // Include lib ref so createResource refetches when the library switches.
    const lib = selectedLibrary();
    return {
      limit: PAGE_SIZE,
      start: parseInt((searchParams.start as string) || "0", 10),
      sort: sort(),
      direction: direction(),
      _lib: lib ? `${lib.type}:${lib.id}` : undefined,
    };
  };

  const [result] = createResource(params, ({ _lib: _, ...rest }) => getTrashItems(rest));

  function handleSort(field: string, dir: "asc" | "desc") {
    setSearchParams({ sort: field, direction: dir, start: undefined });
  }

  const page = () => Math.floor(parseInt((searchParams.start as string) || "0", 10) / PAGE_SIZE);
  const totalPages = () => Math.ceil((result()?.totalResults || 0) / PAGE_SIZE);

  return (
    <>
      <h2 class="text-lg font-semibold mb-4">Trash</h2>

      <Show when={result.loading}>
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
    </>
  );
}
