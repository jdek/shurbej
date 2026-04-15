import { createSignal, For, Show } from "solid-js";
import { A, useLocation } from "@solidjs/router";
import { getCollections, patchCollection, deleteCollection, type ZoteroCollection } from "../api/collections";
import { getTags } from "../api/tags";
import { createCachedResource } from "../lib/query-cache";
import { selectedTags, toggleTag, clearTags, tagColors, setTagColor, removeTagColor } from "../lib/tags";
import CreateCollectionModal from "./CreateCollectionModal";

const TAG_PALETTE = [
  "#e06c6c", "#e0a86c", "#d6d65e", "#6ce08c", "#6cc8e0",
  "#7c9ae0", "#b07ce0", "#e07cb0", "#888888",
];

function buildTree(collections: ZoteroCollection[]) {
  const roots: ZoteroCollection[] = [];
  const children = new Map<string, ZoteroCollection[]>();
  for (const c of collections) {
    const parent = c.data.parentCollection;
    if (parent && parent !== (false as unknown)) {
      const list = children.get(parent) || [];
      list.push(c);
      children.set(parent, list);
    } else {
      roots.push(c);
    }
  }
  roots.sort((a, b) => a.data.name.localeCompare(b.data.name));
  return { roots, children };
}

function CollectionNode(props: {
  collection: ZoteroCollection;
  children: Map<string, ZoteroCollection[]>;
  depth: number;
  onRefresh: () => void;
  draggedKey: () => string | null;
  setDraggedKey: (k: string | null) => void;
}) {
  const loc = useLocation();
  const subs = () => props.children.get(props.collection.key) || [];
  const active = () => loc.pathname === `/collections/${props.collection.key}`;

  const [showCtx, setShowCtx] = createSignal(false);
  const [ctxPos, setCtxPos] = createSignal({ x: 0, y: 0 });
  const [editing, setEditing] = createSignal(false);
  const [editName, setEditName] = createSignal("");
  const [showNewSub, setShowNewSub] = createSignal(false);
  const [dropTarget, setDropTarget] = createSignal(false);

  function handleContext(e: MouseEvent) {
    e.preventDefault();
    setCtxPos({ x: e.clientX, y: e.clientY });
    setShowCtx(true);
    const close = () => { setShowCtx(false); window.removeEventListener("click", close); };
    setTimeout(() => window.addEventListener("click", close), 0);
  }

  function startRename() {
    setEditName(props.collection.data.name);
    setEditing(true);
    setShowCtx(false);
  }

  async function submitRename() {
    if (!editing()) return;
    const n = editName().trim();
    setEditing(false);
    if (!n || n === props.collection.data.name) return;
    await patchCollection(props.collection.key, { name: n }, props.collection.version);
    props.onRefresh();
  }

  async function handleDelete() {
    setShowCtx(false);
    if (!confirm(`Delete collection "${props.collection.data.name}"?`)) return;
    await deleteCollection(props.collection.key, props.collection.version);
    props.onRefresh();
  }

  // -- Drag to reorder/reparent --
  function handleDragStart(e: DragEvent) {
    props.setDraggedKey(props.collection.key);
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", props.collection.key);
    }
  }

  function handleDragOver(e: DragEvent) {
    const dragged = props.draggedKey();
    if (!dragged || dragged === props.collection.key) return;
    e.preventDefault();
    setDropTarget(true);
  }

  function handleDragLeave() {
    setDropTarget(false);
  }

  async function handleDrop(e: DragEvent) {
    e.preventDefault();
    setDropTarget(false);
    const draggedKey = props.draggedKey();
    if (!draggedKey || draggedKey === props.collection.key) return;
    props.setDraggedKey(null);
    // find the dragged collection to get its version
    const allCollections = findAllCollections(props.children, draggedKey);
    if (!allCollections) return;
    await patchCollection(draggedKey, { parentCollection: props.collection.key }, allCollections.version);
    props.onRefresh();
  }

  function handleDragEnd() {
    props.setDraggedKey(null);
  }

  return (
    <>
      <Show when={editing()} fallback={
        <A
          href={`/collections/${props.collection.key}`}
          class="flex items-center gap-2 px-2 py-1 rounded text-sm text-dim hover:bg-surface hover:text-white"
          classList={{
            "bg-surface !text-accent": active(),
            "outline outline-1 outline-accent": dropTarget(),
          }}
          style={{ "padding-left": `${8 + props.depth * 14}px` }}
          onContextMenu={handleContext}
          draggable={true}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
          onDragEnd={handleDragEnd}
        >
          <span class="truncate">{props.collection.data.name}</span>
          <Show when={props.collection.meta.numItems}>
            <span class="ml-auto text-xs text-faint">{props.collection.meta.numItems}</span>
          </Show>
        </A>
      }>
        <div class="flex items-center gap-1 px-1" style={{ "padding-left": `${8 + props.depth * 14}px` }}>
          <input
            class="flex-1 bg-bg border border-accent rounded px-1.5 py-0.5 text-sm outline-none"
            value={editName()}
            onInput={(e) => setEditName(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                e.currentTarget.blur();
              }
              if (e.key === "Escape") {
                setEditing(false);
              }
            }}
            onBlur={submitRename}
            ref={(el) => setTimeout(() => el.focus(), 0)}
          />
        </div>
      </Show>

      {/* Context menu */}
      <Show when={showCtx()}>
        <div
          class="fixed z-50 bg-raised border border-border rounded-md shadow-lg py-1 text-sm min-w-[140px]"
          style={{ left: `${ctxPos().x}px`, top: `${ctxPos().y}px` }}
        >
          <button class="w-full text-left px-3 py-1 hover:bg-surface text-dim hover:text-white" onClick={startRename}>Rename</button>
          <button class="w-full text-left px-3 py-1 hover:bg-surface text-dim hover:text-white" onClick={() => { setShowNewSub(true); setShowCtx(false); }}>New Subcollection</button>
          <button class="w-full text-left px-3 py-1 hover:bg-surface text-danger" onClick={handleDelete}>Delete</button>
        </div>
      </Show>

      <Show when={showNewSub()}>
        <CreateCollectionModal
          parentKey={props.collection.key}
          onClose={() => setShowNewSub(false)}
          onCreated={props.onRefresh}
        />
      </Show>

      <For each={subs()}>
        {(child) => (
          <CollectionNode
            collection={child}
            children={props.children}
            depth={props.depth + 1}
            onRefresh={props.onRefresh}
            draggedKey={props.draggedKey}
            setDraggedKey={props.setDraggedKey}
          />
        )}
      </For>
    </>
  );
}

/** Find a collection by key from the tree to get its version for patching */
function findAllCollections(children: Map<string, ZoteroCollection[]>, key: string): ZoteroCollection | null {
  for (const list of children.values()) {
    for (const c of list) {
      if (c.key === key) return c;
    }
  }
  return null;
}

function TagColorPicker(props: { tag: string; onClose: () => void }) {
  const current = () => tagColors()[props.tag];
  return (
    <div
      class="fixed z-50 bg-raised border border-border rounded-md shadow-lg p-2"
      style={{ left: "60px", top: "50%" }}
    >
      <div class="grid grid-cols-5 gap-1 mb-1">
        <For each={TAG_PALETTE}>
          {(color) => (
            <button
              class="w-5 h-5 rounded-full border-2 transition-transform hover:scale-110"
              classList={{ "border-white": current() === color, "border-transparent": current() !== color }}
              style={{ background: color }}
              onClick={() => { setTagColor(props.tag, color); props.onClose(); }}
            />
          )}
        </For>
      </div>
      <Show when={current()}>
        <button
          class="w-full text-xs text-dim hover:text-white mt-1"
          onClick={() => { removeTagColor(props.tag); props.onClose(); }}
        >
          Remove color
        </button>
      </Show>
    </div>
  );
}

export default function Sidebar() {
  const loc = useLocation();
  const [collections, { refetch: refetchCollections, loading: collectionsLoading }] = createCachedResource(
    () => "collections",
    () => getCollections(),
  );
  const [tags, { loading: tagsLoading }] = createCachedResource(
    () => "tags",
    () => getTags(),
  );
  const [showNewCollection, setShowNewCollection] = createSignal(false);
  const [colorPickerTag, setColorPickerTag] = createSignal<string | null>(null);
  const [draggedKey, setDraggedKey] = createSignal<string | null>(null);
  const [rootDropTarget, setRootDropTarget] = createSignal(false);

  const tree = () => {
    const data = collections();
    if (!data) return { roots: [], children: new Map<string, ZoteroCollection[]>() };
    return buildTree(data);
  };

  // Also build a flat lookup for drag-drop version lookups
  const collectionMap = () => {
    const data = collections();
    if (!data) return new Map<string, ZoteroCollection>();
    return new Map(data.map((c) => [c.key, c]));
  };

  // Drop on "All Items" = move to root
  async function handleRootDrop(e: DragEvent) {
    e.preventDefault();
    setRootDropTarget(false);
    const key = draggedKey();
    if (!key) return;
    setDraggedKey(null);
    const coll = collectionMap().get(key);
    if (!coll) return;
    await patchCollection(key, { parentCollection: false }, coll.version);
    refetchCollections();
  }

  // Sort tags: colored ones first, then alphabetical
  const sortedTags = () => {
    const all = tags() || [];
    const colors = tagColors();
    return [...all].sort((a, b) => {
      const ac = colors[a.tag] ? 0 : 1;
      const bc = colors[b.tag] ? 0 : 1;
      if (ac !== bc) return ac - bc;
      return a.tag.localeCompare(b.tag);
    });
  };

  return (
    <nav class="border-r border-border overflow-y-auto py-2 flex flex-col">
      <div class="px-3 space-y-0.5">
        <A
          href="/"
          class="flex items-center px-2 py-1 rounded text-sm text-dim hover:bg-surface hover:text-white"
          classList={{
            "bg-surface !text-accent": loc.pathname === "/",
            "outline outline-1 outline-accent": rootDropTarget(),
          }}
          onClick={() => clearTags()}
          onDragOver={(e) => {
            if (draggedKey()) { e.preventDefault(); setRootDropTarget(true); }
          }}
          onDragLeave={() => setRootDropTarget(false)}
          onDrop={handleRootDrop}
        >
          All Items
        </A>
        <A
          href="/trash"
          class="flex items-center px-2 py-1 rounded text-sm text-dim hover:bg-surface hover:text-white"
          classList={{ "bg-surface !text-accent": loc.pathname === "/trash" }}
        >
          Trash
        </A>
      </div>

      <div class="px-3 mt-4">
        <div class="flex items-center justify-between px-2 mb-1">
          <span class="text-[11px] uppercase tracking-wide text-faint">Collections</span>
          <button
            class="text-faint hover:text-white text-xs px-1"
            title="New collection"
            onClick={() => setShowNewCollection(true)}
          >+</button>
        </div>
        <Show when={!collectionsLoading() || collections()} fallback={<div class="text-sm text-dim px-2">Loading...</div>}>
          <div class="space-y-0.5">
            <For each={tree().roots} fallback={<div class="text-sm text-faint px-2">No collections</div>}>
              {(c) => (
                <CollectionNode
                  collection={c}
                  children={tree().children}
                  depth={0}
                  onRefresh={refetchCollections}
                  draggedKey={draggedKey}
                  setDraggedKey={setDraggedKey}
                />
              )}
            </For>
          </div>
        </Show>
      </div>

      {/* Tags section */}
      <div class="px-3 mt-4 flex-1 min-h-0 flex flex-col">
        <div class="flex items-center justify-between px-2 mb-1">
          <span class="text-[11px] uppercase tracking-wide text-faint">Tags</span>
          <Show when={selectedTags().length > 0}>
            <button class="text-[10px] text-dim hover:text-white" onClick={clearTags}>clear</button>
          </Show>
        </div>
        <div class="overflow-y-auto flex-1 min-h-0">
          <Show when={!tagsLoading() || tags()}>
            <div class="flex flex-wrap gap-1 px-2">
              <For each={sortedTags()}>
                {(t) => {
                  const isSelected = () => selectedTags().includes(t.tag);
                  const color = () => tagColors()[t.tag];
                  return (
                    <button
                      class="text-xs px-2 py-0.5 rounded-full border transition-colors max-w-full truncate"
                      classList={{
                        "border-accent text-white": isSelected() && !color(),
                        "border-border text-dim hover:text-white": !isSelected() && !color(),
                      }}
                      style={{
                        ...(color() ? {
                          "border-color": color(),
                          color: isSelected() ? "#fff" : color(),
                          background: isSelected() ? color() : "transparent",
                        } : {}),
                      }}
                      title={t.tag}
                      onClick={() => toggleTag(t.tag)}
                      onContextMenu={(e) => {
                        e.preventDefault();
                        setColorPickerTag(colorPickerTag() === t.tag ? null : t.tag);
                      }}
                    >
                      {t.tag}
                    </button>
                  );
                }}
              </For>
            </div>
          </Show>
        </div>
      </div>

      <Show when={colorPickerTag()}>
        <TagColorPicker tag={colorPickerTag()!} onClose={() => setColorPickerTag(null)} />
      </Show>

      <Show when={showNewCollection()}>
        <CreateCollectionModal
          onClose={() => setShowNewCollection(false)}
          onCreated={refetchCollections}
        />
      </Show>
    </nav>
  );
}
