import { For, createSignal, createEffect, on } from "solid-js";
import "pdfjs-viewer-element";
import { apiKey } from "../lib/auth";
import { activeTab, tabs } from "../lib/tabs";

const MAX_INSTANCES = 5;

function authHeaders(): Record<string, string> {
  const h: Record<string, string> = { "Zotero-API-Version": "3" };
  const key = apiKey();
  if (key) h["Zotero-API-Key"] = key;
  return h;
}

function absUrl(path: string): string {
  if (path.startsWith("http")) return path;
  return `${window.location.origin}${path}`;
}

// Track viewer state outside reactivity
const viewerEls: Map<string, HTMLElement> = new Map();
const loadedKeys: Set<string> = new Set();

export default function PdfViewer() {
  const [slotKeys, setSlotKeys] = createSignal<string[]>([]);
  const [errorKey, setErrorKey] = createSignal<string | null>(null);
  const [errorMsg, setErrorMsg] = createSignal<string | null>(null);

  const activePdfKey = () => {
    const tabId = activeTab();
    const tab = tabs().find((t) => t.id === tabId && t.type === "pdf");
    return tab?.itemKey ?? null;
  };

  // Track LRU order separately — don't reorder slotKeys (that destroys DOM)
  const lruOrder: string[] = [];

  function touchLru(key: string) {
    const idx = lruOrder.indexOf(key);
    if (idx >= 0) lruOrder.splice(idx, 1);
    lruOrder.push(key);
  }

  // Manage slot list when active tab changes
  createEffect(on(activeTab, (tabId) => {
    const tab = tabs().find((t) => t.id === tabId && t.type === "pdf");
    if (!tab?.itemKey) return;

    const key = tab.itemKey;
    touchLru(key);

    const current = slotKeys();
    if (current.includes(key)) return; // already has a slot

    // Evict oldest if at capacity
    if (current.length >= MAX_INSTANCES) {
      const evictKey = lruOrder.find((k) => k !== key && current.includes(k));
      if (evictKey) {
        viewerEls.delete(evictKey);
        loadedKeys.delete(evictKey);
        const idx = lruOrder.indexOf(evictKey);
        if (idx >= 0) lruOrder.splice(idx, 1);
        setSlotKeys([...current.filter((k) => k !== evictKey), key]);
        return;
      }
    }

    setSlotKeys([...current, key]);
  }));

  // When a ref is captured, store it and trigger load
  function captureRef(el: HTMLElement, itemKey: string) {
    viewerEls.set(itemKey, el);
    // Trigger load after the element is connected
    if (!loadedKeys.has(itemKey)) {
      requestAnimationFrame(() => loadViewer(itemKey));
    }
  }

  async function loadViewer(itemKey: string) {
    if (loadedKeys.has(itemKey)) return;

    const el = viewerEls.get(itemKey);
    if (!el) return;

    const tab = tabs().find((t) => t.itemKey === itemKey && t.type === "pdf");
    if (!tab?.fetchUrl) return;

    const url = absUrl(tab.fetchUrl);
    setErrorKey(null);
    setErrorMsg(null);

    try {
      const ve = el as any;
      // Wait for connectedCallback to reassign initPromise
      await new Promise((r) => requestAnimationFrame(r));
      const { viewerApp } = await ve.initPromise;
      const app = viewerApp || ve.iframe?.contentWindow?.PDFViewerApplication;
      if (!app) throw new Error("PDF viewer failed to initialize");

      el.setAttribute("viewer-css-theme", "DARK");

      await app.open({ url, httpHeaders: authHeaders() });
      loadedKeys.add(itemKey);
    } catch (err) {
      setErrorKey(itemKey);
      setErrorMsg(String(err));
    } finally {
      // noop
    }
  }

  return (
    <For each={slotKeys()}>
      {(itemKey) => {
        const isActive = () => activePdfKey() === itemKey;
        const isError = () => errorKey() === itemKey;

        return (
          <div
            class="absolute inset-0"
            classList={{
              "z-10": isActive(),
              "z-0 pointer-events-none opacity-0": !isActive(),
            }}
          >
            {isError() && isActive() && (
              <div class="absolute inset-0 flex items-center justify-center bg-bg text-danger text-sm z-10">
                Failed to load PDF: {errorMsg()}
              </div>
            )}
            {/* @ts-expect-error custom element */}
            <pdfjs-viewer-element
              ref={(el: HTMLElement) => captureRef(el, itemKey)}
              style={{ width: "100%", height: "100%", display: "block" }}
            />
          </div>
        );
      }}
    </For>
  );
}
