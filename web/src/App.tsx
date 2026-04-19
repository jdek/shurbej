import { Show, Suspense, createMemo, createEffect, lazy } from "solid-js";
import { Router, Route } from "@solidjs/router";
import { apiKey, userId, logout } from "./lib/auth";
import { tabs, activeTab, switchTab } from "./lib/tabs";
import { setLibraries, libraries } from "./lib/library";
import { getGroups } from "./api/groups";
import Sidebar from "./components/Sidebar";
import TabBar from "./components/TabBar";
import Login from "./pages/Login";
import Library from "./pages/Library";
import ItemDetail from "./pages/ItemDetail";
import CollectionView from "./pages/CollectionView";
import Trash from "./pages/Trash";

const PdfViewer = lazy(() => import("./components/PdfViewer"));

function Shell(props: { children?: any }) {
  const isLibrary = () => activeTab() === "library";
  const hasPdfTabs = createMemo(() => tabs().some((t) => t.type === "pdf"));

  return (
    <div class="flex flex-col h-screen">
      <header class="flex items-center gap-3 px-4 h-10 shrink-0 bg-raised border-b border-border">
        <h1
          class="text-base font-semibold mr-3 cursor-pointer"
          onClick={() => switchTab("library")}
        >
          Shurbej
        </h1>
        <TabBar />
        <button class="ml-auto text-xs px-2 py-1 border border-border rounded hover:bg-surface shrink-0" onClick={logout}>
          Sign out
        </button>
      </header>

      <div class="flex-1 min-h-0 relative">
        {/* Library view — sidebar + content */}
        <div
          class="absolute inset-0 flex"
          style={{ "z-index": isLibrary() ? "1" : "0", visibility: isLibrary() ? "visible" : "hidden" }}
        >
          <div class="w-60 shrink-0 overflow-y-auto">
            <Sidebar />
          </div>
          <main class="flex-1 overflow-y-auto p-4 px-6">
            {props.children}
          </main>
        </div>

        {/* PDF viewer — stacked behind/in front of library */}
        <Show when={hasPdfTabs()}>
          <div
            class="absolute inset-0"
            style={{ "z-index": isLibrary() ? "0" : "1", visibility: isLibrary() ? "hidden" : "visible" }}
          >
            <Suspense fallback={<div class="flex items-center justify-center h-full text-dim">Loading viewer...</div>}>
              <PdfViewer />
            </Suspense>
          </div>
        </Show>
      </div>
    </div>
  );
}

function GuardedShell(props: { children?: any }) {
  // Seed the libraries list (user + groups) once we know who we are.
  createEffect(() => {
    const uid = userId();
    if (!apiKey() || uid == null) return;
    if (libraries().length > 0) return;
    (async () => {
      let groups: { id: number; data: { name: string } }[] = [];
      try {
        groups = await getGroups();
      } catch {
        groups = [];
      }
      setLibraries([
        { type: "user", id: uid, name: "My Library" },
        ...groups.map((g) => ({
          type: "group" as const,
          id: g.id,
          name: g.data.name,
        })),
      ]);
    })();
  });

  return (
    <Show when={apiKey() && userId()} fallback={<Login />}>
      <Shell>{props.children}</Shell>
    </Show>
  );
}

export default function App() {
  return (
    <Router root={GuardedShell}>
      <Route path="/" component={Library} />
      <Route path="/items/:key" component={ItemDetail} />
      <Route path="/collections/:key" component={CollectionView} />
      <Route path="/trash" component={Trash} />
    </Router>
  );
}
