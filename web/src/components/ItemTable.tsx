import { createSignal, For, Show, onMount, onCleanup, type Component } from "solid-js";
import { A } from "@solidjs/router";
import { prepareWithSegments, layoutNextLine } from "@chenglou/pretext";
import type { PreparedTextWithSegments } from "@chenglou/pretext";
import BookOpen from "lucide-solid/icons/book-open";
import FileText from "lucide-solid/icons/file-text";
import ScrollText from "lucide-solid/icons/scroll-text";
import Newspaper from "lucide-solid/icons/newspaper";
import Building2 from "lucide-solid/icons/building-2";
import GraduationCap from "lucide-solid/icons/graduation-cap";
import ClipboardList from "lucide-solid/icons/clipboard-list";
import Globe from "lucide-solid/icons/globe";
import Paperclip from "lucide-solid/icons/paperclip";
import StickyNote from "lucide-solid/icons/sticky-note";
import Mail from "lucide-solid/icons/mail";
import Scale from "lucide-solid/icons/scale";
import Presentation from "lucide-solid/icons/presentation";
import FilmIcon from "lucide-solid/icons/film";
import Headphones from "lucide-solid/icons/headphones";
import Video from "lucide-solid/icons/video";
import Music from "lucide-solid/icons/music";
import MapIcon from "lucide-solid/icons/map";
import Monitor from "lucide-solid/icons/monitor";
import PenLine from "lucide-solid/icons/pen-line";
import MessageCircle from "lucide-solid/icons/message-circle";
import FileEdit from "lucide-solid/icons/file-pen-line";
import FileIcon from "lucide-solid/icons/file";
import type { ZoteroItem } from "../api/items";
import {
  columns, addColumn, removeColumn, reorderColumn, resizeDivider,
  getColumnDef, ALL_COLUMNS, type ColumnState,
} from "../lib/columns";
import { tagColors } from "../lib/tags";

// ---------------------------------------------------------------------------
// Data formatters
// ---------------------------------------------------------------------------

function formatCreators(item: ZoteroItem): string {
  const creators = item.data.creators;
  if (!creators?.length) return "";
  const surnames = creators
    .map((c) => c.name || c.lastName || "")
    .filter(Boolean);
  if (surnames.length === 0) return "";
  if (surnames.length === 1) return surnames[0];
  if (surnames.length === 2) return `${surnames[0]} and ${surnames[1]}`;
  return `${surnames[0]} et al.`;
}

function formatDate(iso?: string): string {
  if (!iso) return "";
  try { return new Date(iso).toLocaleDateString(); } catch { return iso; }
}

function getYear(item: ZoteroItem): string {
  const d = item.data.date as string | undefined;
  if (!d) return "";
  const m = d.match(/\d{4}/);
  return m ? m[0] : d;
}

function cellValue(colId: string, item: ZoteroItem): string {
  switch (colId) {
    case "creator": return formatCreators(item);
    case "itemType": return item.data.itemType;
    case "dateModified": return formatDate(item.data.dateModified);
    case "dateAdded": return formatDate(item.data.dateAdded);
    case "year": return getYear(item);
    case "publisher": return (item.data as Record<string, unknown>).publisher as string || "";
    case "publicationTitle": return (item.data as Record<string, unknown>).publicationTitle as string || "";
    case "attachments": return item.meta.numChildren ? `${item.meta.numChildren}` : "";
    default: return "";
  }
}

// ---------------------------------------------------------------------------
// Title truncation (pretext.js — proper font-aware word-boundary truncation)
// ---------------------------------------------------------------------------

const TABLE_FONT = "14px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";
const ELLIPSIS = "\u2026";

// Cache prepared texts to avoid re-measuring on every render
const preparedCache: Map<string, PreparedTextWithSegments> = new globalThis.Map();
function getPrepared(text: string) {
  let p = preparedCache.get(text);
  if (!p) {
    p = prepareWithSegments(text, TABLE_FONT);
    preparedCache.set(text, p);
    if (preparedCache.size > 2000) {
      const first = preparedCache.keys().next();
      if (!first.done) preparedCache.delete(first.value);
    }
  }
  return p;
}

function truncateForWidth(text: string, maxWidth: number): { display: string; truncated: boolean } {
  if (maxWidth <= 0) return { display: text, truncated: false };
  const prepared = getPrepared(text);
  const firstLine = layoutNextLine(prepared, { segmentIndex: 0, graphemeIndex: 0 }, maxWidth);
  if (!firstLine) return { display: text, truncated: false };
  // check if the entire text fit on the first line
  const secondLine = layoutNextLine(prepared, firstLine.end, maxWidth);
  if (!secondLine) return { display: firstLine.text, truncated: false };
  // text overflows — use first line text with ellipsis
  // re-layout with slightly less width to make room for the ellipsis
  const ellipsisPrep = getPrepared(ELLIPSIS);
  const ellipsisLine = layoutNextLine(ellipsisPrep, { segmentIndex: 0, graphemeIndex: 0 }, maxWidth);
  const ellipsisW = ellipsisLine?.width ?? 8;
  const trimmedLine = layoutNextLine(prepared, { segmentIndex: 0, graphemeIndex: 0 }, maxWidth - ellipsisW);
  const display = (trimmedLine?.text.trimEnd() ?? text.slice(0, 10)) + ELLIPSIS;
  return { display, truncated: true };
}

const TYPE_ICONS: Record<string, Component<{ size?: number; class?: string }>> = {
  book: BookOpen,
  bookSection: BookOpen,
  journalArticle: ScrollText,
  magazineArticle: Newspaper,
  newspaperArticle: Newspaper,
  conferencePaper: Building2,
  thesis: GraduationCap,
  report: ClipboardList,
  webpage: Globe,
  attachment: Paperclip,
  note: StickyNote,
  letter: Mail,
  email: Mail,
  patent: Scale,
  statute: Scale,
  case: Scale,
  bill: Scale,
  presentation: Presentation,
  film: FilmIcon,
  podcast: Headphones,
  videoRecording: Video,
  audioRecording: Music,
  map: MapIcon,
  computerProgram: Monitor,
  blogPost: PenLine,
  forumPost: MessageCircle,
  manuscript: FileEdit,
  document: FileText,
  preprint: ScrollText,
};

function TypeIcon(props: { itemType: string }) {
  const Icon = () => TYPE_ICONS[props.itemType] ?? FileIcon;
  return <>{(() => { const I = Icon(); return <I size={14} class="text-faint" />; })()}</>;
}

function TruncatedTitle(props: { text: string; href: string; itemType: string; numChildren?: number; hasAttachCol: boolean }) {
  let containerRef!: HTMLDivElement;
  const [measuredWidth, setMeasuredWidth] = createSignal(400);

  onMount(() => {
    if (containerRef) setMeasuredWidth(containerRef.offsetWidth);
    const ro = new ResizeObserver(() => {
      if (containerRef) setMeasuredWidth(containerRef.offsetWidth);
    });
    ro.observe(containerRef);
    onCleanup(() => ro.disconnect());
  });

  const availableWidth = () => {
    let w = measuredWidth();
    if (props.numChildren && !props.hasAttachCol) w -= 30;
    return Math.max(40, w);
  };

  const result = () => truncateForWidth(props.text, availableWidth());

  return (
    <div ref={containerRef} class="flex items-center gap-1.5 min-w-0">
      <span class="shrink-0" title={props.itemType}><TypeIcon itemType={props.itemType} /></span>
      <A
        href={props.href}
        class="hover:text-accent whitespace-nowrap overflow-hidden"
        title={result().truncated ? props.text : undefined}
      >
        {result().display}
      </A>
      <Show when={props.numChildren && !props.hasAttachCol}>
        <span class="text-faint text-xs shrink-0">+{props.numChildren}</span>
      </Show>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

interface Props {
  items: ZoteroItem[];
  sort?: string;
  direction?: "asc" | "desc";
  onSort?: (field: string, dir: "asc" | "desc") => void;
}

export default function ItemTable(props: Props) {
  const [ctxMenu, setCtxMenu] = createSignal<{ x: number; y: number } | null>(null);
  const [dragFrom, setDragFrom] = createSignal<number | null>(null);
  const [dragOver, setDragOver] = createSignal<number | null>(null);

  const cols = () => columns();
  const hasAttachCol = () => cols().some((c) => c.id === "attachments");
  const colors = tagColors;

  function closeCtx() { setCtxMenu(null); }

  // -- Sort --
  function handleHeaderClick(colId: string) {
    const def = getColumnDef(colId);
    if (!def?.sortKey || !props.onSort) return;
    const newDir: "asc" | "desc" =
      props.sort === def.sortKey && props.direction === "asc" ? "desc" : "asc";
    props.onSort(def.sortKey, newDir);
  }

  function sortIndicator(colId: string): string {
    const def = getColumnDef(colId);
    if (!def?.sortKey || def.sortKey !== props.sort) return "";
    return props.direction === "asc" ? " \u25B2" : " \u25BC";
  }

  // -- Header context menu --
  function handleHeaderContext(e: MouseEvent) {
    e.preventDefault();
    setCtxMenu({ x: e.clientX, y: e.clientY });
    setTimeout(() => window.addEventListener("click", closeCtx, { once: true }), 0);
  }

  // -- Resize divider between col[idx] and col[idx+1] --
  function startResize(e: MouseEvent, idx: number) {
    e.preventDefault();
    e.stopPropagation();
    const startX = e.clientX;

    let lastX = startX;
    function onMoveAccum(ev: MouseEvent) {
      const delta = ev.clientX - lastX;
      if (Math.abs(delta) > 2) {
        resizeDivider(idx, delta);
        lastX = ev.clientX;
      }
    }

    function onUp() {
      window.removeEventListener("mousemove", onMoveAccum);
      window.removeEventListener("mouseup", onUp);
    }
    window.addEventListener("mousemove", onMoveAccum);
    window.addEventListener("mouseup", onUp);
  }

  // -- Column reorder --
  function handleDragStart(e: DragEvent, idx: number) {
    setDragFrom(idx);
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(idx));
    }
  }

  function handleDragOver(e: DragEvent, idx: number) {
    e.preventDefault();
    setDragOver(idx);
  }

  function handleDrop(e: DragEvent, toIdx: number) {
    e.preventDefault();
    const fromIdx = dragFrom();
    if (fromIdx !== null && fromIdx !== toIdx) {
      reorderColumn(fromIdx, toIdx);
    }
    setDragFrom(null);
    setDragOver(null);
  }

  function handleDragEnd() {
    setDragFrom(null);
    setDragOver(null);
  }

  // -- Render cell --
  function renderCell(col: ColumnState, item: ZoteroItem) {
    const tdClass = "py-2 px-2.5 border-b border-border overflow-hidden";
    if (col.id === "title") {
      return (
        <td class={tdClass}>
          <TruncatedTitle
            text={item.data.title || item.data.name || item.key}
            href={`/items/${item.key}`}
            itemType={item.data.itemType}
            numChildren={item.meta.numChildren}
            hasAttachCol={hasAttachCol()}
          />
        </td>
      );
    }
    if (col.id === "itemType") {
      return (
        <td class={tdClass}>
          <span class="text-[11px] px-1.5 py-0.5 rounded bg-surface text-dim inline-block max-w-full truncate align-bottom" title={item.data.itemType}>
            {item.data.itemType}
          </span>
        </td>
      );
    }
    if (col.id === "tags") {
      return (
        <td class={tdClass}>
          <div class="flex flex-nowrap gap-0.5 overflow-hidden">
            <For each={item.data.tags?.slice(0, 5)}>
              {(t) => {
                const c = colors()[t.tag];
                return (
                  <span
                    class="text-[10px] px-1.5 py-0 rounded-full border truncate shrink-0 max-w-full"
                    style={c
                      ? { "border-color": c, color: c }
                      : { "border-color": "var(--color-border)", color: "var(--color-dim)" }
                    }
                    title={t.tag}
                  >
                    {t.tag}
                  </span>
                );
              }}
            </For>
          </div>
        </td>
      );
    }
    const val = cellValue(col.id, item);
    return (
      <td class={`${tdClass} text-dim text-[13px]`}>
        <div class="truncate" title={val || undefined}>{val}</div>
      </td>
    );
  }

  return (
    <div class="relative">
      <table class="w-full border-collapse text-sm table-fixed">
        <colgroup>
          <For each={cols()}>
            {(col) => (
              <col style={col.id === "title" ? {} : { width: `${col.width}px` }} />
            )}
          </For>
        </colgroup>
        <thead>
          <tr class="text-left text-[11px] uppercase tracking-wide text-faint select-none">
            <For each={cols()}>
              {(col, idx) => {
                const def = getColumnDef(col.id);
                const sortable = !!def?.sortKey;
                const isLast = () => idx() === cols().length - 1;
                return (
                  <th
                    class="relative py-1.5 px-2.5 border-b border-border font-medium"
                    classList={{
                      "cursor-pointer hover:text-white": sortable,
                      "bg-surface/50": dragOver() === idx(),
                    }}
                    draggable={true}
                    onClick={() => handleHeaderClick(col.id)}
                    onContextMenu={handleHeaderContext}
                    onDragStart={(e) => handleDragStart(e, idx())}
                    onDragOver={(e) => handleDragOver(e, idx())}
                    onDrop={(e) => handleDrop(e, idx())}
                    onDragEnd={handleDragEnd}
                  >
                    <span class="pointer-events-none">{def?.label}{sortIndicator(col.id)}</span>
                    {/* Resize handle on right edge — acts as divider between this col and next */}
                    <Show when={!isLast()}>
                      <div
                        class="absolute right-0 top-0 bottom-0 w-[5px] cursor-col-resize z-10 hover:bg-accent/40"
                        onMouseDown={(e) => startResize(e, idx())}
                      />
                    </Show>
                  </th>
                );
              }}
            </For>
          </tr>
        </thead>
        <tbody>
          <For each={props.items} fallback={
            <tr><td colspan={cols().length} class="text-center py-12 text-faint">No items</td></tr>
          }>
            {(item) => (
              <tr class="hover:bg-surface">
                <For each={cols()}>
                  {(col) => renderCell(col, item)}
                </For>
              </tr>
            )}
          </For>
        </tbody>
      </table>

      {/* Right-click context menu */}
      <Show when={ctxMenu()}>
        {(menu) => (
          <>
            <div class="fixed inset-0 z-40" onClick={closeCtx} />
            <div
              class="fixed z-50 bg-raised border border-border rounded-md shadow-lg py-1 text-sm min-w-[160px]"
              style={{ left: `${menu().x}px`, top: `${menu().y}px` }}
            >
              <div class="px-3 py-1 text-[10px] uppercase tracking-wide text-faint">Columns</div>
              <For each={ALL_COLUMNS}>
                {(def) => {
                  const active = () => cols().some((c) => c.id === def.id);
                  const locked = def.id === "title";
                  return (
                    <button
                      class="w-full text-left px-3 py-1 hover:bg-surface flex items-center gap-2"
                      classList={{
                        "text-white": active(),
                        "text-dim": !active(),
                        "opacity-50 cursor-default": locked,
                      }}
                      onClick={() => {
                        if (locked) return;
                        if (active()) removeColumn(def.id);
                        else addColumn(def.id);
                        closeCtx();
                      }}
                    >
                      <span class="w-3 text-[10px]">{active() ? "\u2713" : ""}</span>
                      {def.label}
                    </button>
                  );
                }}
              </For>
            </div>
          </>
        )}
      </Show>
    </div>
  );
}
