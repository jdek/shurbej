import { createResource, createSignal, For, Show } from "solid-js";
import { useParams, useNavigate, A } from "@solidjs/router";
import { getItem, getChildren, deleteItem, patchItem, type ZoteroItem } from "../api/items";
import { userPath } from "../api/client";
import { openPdfTab } from "../lib/tabs";

const API_BASE = import.meta.env.DEV ? "/api" : "";

const SKIP_FIELDS = new Set([
  "key", "version", "itemType", "tags", "creators", "collections",
  "relations", "dateAdded", "dateModified", "deleted",
]);

function formatCreator(c: NonNullable<ZoteroItem["data"]["creators"]>[0]) {
  return c.name || [c.firstName, c.lastName].filter(Boolean).join(" ");
}

function isPdf(child: ZoteroItem): boolean {
  if (child.data.itemType !== "attachment") return false;
  const ct = (child.data as Record<string, unknown>).contentType as string | undefined;
  return ct === "application/pdf";
}

export default function ItemDetail() {
  const params = useParams<{ key: string }>();
  const navigate = useNavigate();
  const [item, { refetch }] = createResource(() => params.key, getItem);
  const [children] = createResource(() => params.key, getChildren);
  const [deleting, setDeleting] = createSignal(false);

  async function handleDelete() {
    const it = item();
    if (!it || !confirm("Move this item to trash?")) return;
    setDeleting(true);
    try {
      await deleteItem(it.key, it.version);
      navigate("/", { replace: true });
    } catch {
      setDeleting(false);
    }
  }

  async function handleRestore() {
    const it = item();
    if (!it) return;
    await patchItem(it.key, { deleted: false }, it.version);
    refetch();
  }

  function openPdf(child: ZoteroItem) {
    const url = `${API_BASE}${userPath(`/items/${child.key}/file`)}`;
    // Use parent item title if available, fall back to attachment title
    const parent = item();
    const title = (parent && parent.key !== child.key)
      ? (parent.data.title || parent.data.name || parent.key)
      : (child.data.title || child.data.name || child.key);
    openPdfTab(child.key, title, url);
  }

  const dataFields = () => {
    const it = item();
    if (!it) return [];
    return Object.entries(it.data).filter(
      ([k, v]) => !SKIP_FIELDS.has(k) && v !== "" && v !== null && v !== undefined && v !== false
    );
  };

  const fileUrl = () => {
    const it = item();
    if (!it) return null;
    if (it.data.itemType === "attachment") return `${API_BASE}${userPath(`/items/${it.key}/file`)}`;
    return null;
  };

  function handleOpenSelf() {
    const it = item();
    if (!it) return;
    if (isPdf(it)) {
      openPdf(it);
    }
  }

  return (
    <Show when={item()} fallback={<div class="text-center py-8 text-dim">Loading...</div>}>
      {(it) => (
        <div class="max-w-[720px]">
          <div class="flex gap-2 mb-4">
            <button class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface" onClick={() => navigate(-1)}>Back</button>
            <Show when={it().data.deleted}>
              <button class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface" onClick={handleRestore}>Restore</button>
            </Show>
            <button class="px-3 py-1.5 text-sm border border-danger text-danger rounded-md hover:bg-danger hover:text-bg" onClick={handleDelete} disabled={deleting()}>
              {deleting() ? "Deleting..." : "Delete"}
            </button>
            <Show when={isPdf(it())}>
              <button class="px-3 py-1.5 text-sm border border-accent text-accent rounded-md hover:bg-accent hover:text-bg" onClick={handleOpenSelf}>
                Open PDF
              </button>
            </Show>
            <Show when={fileUrl()}>
              <a href={fileUrl()!} target="_blank" rel="noopener">
                <button type="button" class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface">Download</button>
              </a>
            </Show>
          </div>

          <h2 class="text-xl font-semibold mb-4">
            {it().data.title || it().data.name || it().key}
          </h2>

          <div class="grid grid-cols-[140px_1fr] gap-x-4 gap-y-1.5">
            <div class="text-xs text-faint uppercase tracking-wide pt-0.5">Type</div>
            <div><span class="text-[11px] px-1.5 py-0.5 rounded bg-surface text-dim">{it().data.itemType}</span></div>

            <Show when={it().data.creators?.length}>
              <div class="text-xs text-faint uppercase tracking-wide pt-0.5">Creators</div>
              <div>
                <For each={it().data.creators}>
                  {(c) => (
                    <div>
                      <span class="text-faint text-xs">{c.creatorType}: </span>
                      {formatCreator(c)}
                    </div>
                  )}
                </For>
              </div>
            </Show>

            <For each={dataFields()}>
              {([key, value]) => (
                <>
                  <div class="text-xs text-faint uppercase tracking-wide pt-0.5">{key}</div>
                  <div class="break-words">{String(value)}</div>
                </>
              )}
            </For>

            <div class="text-xs text-faint uppercase tracking-wide pt-0.5">Added</div>
            <div class="text-dim text-[13px]">{it().data.dateAdded}</div>

            <div class="text-xs text-faint uppercase tracking-wide pt-0.5">Modified</div>
            <div class="text-dim text-[13px]">{it().data.dateModified}</div>

            <Show when={it().data.tags?.length}>
              <div class="text-xs text-faint uppercase tracking-wide pt-0.5">Tags</div>
              <div class="flex flex-wrap gap-1">
                <For each={it().data.tags}>
                  {(t) => <span class="text-xs px-2 py-0.5 rounded-full bg-surface border border-border text-dim">{t.tag}</span>}
                </For>
              </div>
            </Show>
          </div>

          <Show when={children()?.length}>
            <div class="mt-6">
              <h3 class="text-sm text-dim mb-2">Attachments & Notes ({children()!.length})</h3>
              <For each={children()}>
                {(child) => (
                  <div class="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-surface">
                    <A href={`/items/${child.key}`} class="flex items-center gap-2 flex-1 min-w-0">
                      <span class="text-[11px] px-1.5 py-0.5 rounded bg-surface text-dim shrink-0">{child.data.itemType}</span>
                      <span class="truncate">{child.data.title || child.data.name || child.key}</span>
                    </A>
                    <Show when={isPdf(child)}>
                      <button
                        class="text-xs px-2 py-0.5 border border-accent text-accent rounded hover:bg-accent hover:text-bg shrink-0"
                        onClick={() => openPdf(child)}
                      >
                        Open PDF
                      </button>
                    </Show>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </div>
      )}
    </Show>
  );
}
