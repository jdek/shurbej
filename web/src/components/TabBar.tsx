import { For } from "solid-js";
import { tabs, activeTab, switchTab, closeTab } from "../lib/tabs";
import ScrollText from "lucide-solid/icons/scroll-text";
import BookOpen from "lucide-solid/icons/book-open";

const TAB_ICONS = {
  library: BookOpen,
  pdf: ScrollText,
};

export default function TabBar() {
  return (
    <div class="flex items-center gap-0 overflow-x-auto min-w-0">
      <For each={tabs()}>
        {(tab) => {
          const isActive = () => activeTab() === tab.id;
          const isLibrary = tab.id === "library";
          const Icon = TAB_ICONS[tab.type] ?? ScrollText;
          return (
            <button
              class="flex items-center gap-1.5 px-3 py-1 text-sm border-b-2 max-w-[200px] shrink-0 transition-colors"
              classList={{
                "border-accent text-white": isActive(),
                "border-transparent text-dim hover:text-white": !isActive(),
              }}
              title={tab.label}
              onClick={() => switchTab(tab.id)}
              onAuxClick={(e) => {
                if (e.button === 1 && !isLibrary) {
                  e.preventDefault();
                  closeTab(tab.id);
                }
              }}
            >
              <Icon size={13} class="shrink-0" />
              <span class="truncate">{tab.label}</span>
              {!isLibrary && (
                <span
                  class="text-faint hover:text-white text-xs leading-none ml-0.5 shrink-0"
                  onClick={(e) => {
                    e.stopPropagation();
                    closeTab(tab.id);
                  }}
                >
                  ×
                </span>
              )}
            </button>
          );
        }}
      </For>
    </div>
  );
}
