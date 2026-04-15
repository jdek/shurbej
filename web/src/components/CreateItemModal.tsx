import { createSignal, createResource, Show, For } from "solid-js";
import { getItemTypes, getItemTemplate, createItems } from "../api/items";

export default function CreateItemModal(props: { onClose: () => void; onCreated: () => void }) {
  const [itemTypes] = createResource(getItemTypes);
  const [selectedType, setSelectedType] = createSignal("book");
  const [template] = createResource(selectedType, getItemTemplate);
  const [title, setTitle] = createSignal("");
  const [saving, setSaving] = createSignal(false);
  const [error, setError] = createSignal("");

  async function handleSubmit(e: Event) {
    e.preventDefault();
    const t = template();
    if (!t) return;
    setSaving(true);
    setError("");
    try {
      await createItems([{ ...t, title: title() }]);
      props.onCreated();
      props.onClose();
    } catch (err) {
      setError(String(err));
    } finally {
      setSaving(false);
    }
  }

  const input = "w-full bg-bg border border-border rounded-md px-3 py-1.5 text-sm outline-none focus:border-accent";

  return (
    <div class="fixed inset-0 bg-black/60 flex items-center justify-center z-50" onClick={(e) => e.target === e.currentTarget && props.onClose()}>
      <form class="bg-raised border border-border rounded-lg p-6 w-[440px]" onSubmit={handleSubmit}>
        <h2 class="text-base font-semibold mb-4">New Item</h2>
        <div class="mb-3">
          <label class="block text-xs text-dim mb-1">Item Type</label>
          <select class={input} value={selectedType()} onChange={(e) => setSelectedType(e.currentTarget.value)}>
            <Show when={itemTypes()}>
              <For each={itemTypes()}>
                {(t) => <option value={t.itemType}>{t.localized}</option>}
              </For>
            </Show>
          </select>
        </div>
        <div class="mb-3">
          <label class="block text-xs text-dim mb-1">Title</label>
          <input type="text" class={input} value={title()} onInput={(e) => setTitle(e.currentTarget.value)} autofocus />
        </div>
        <Show when={error()}>
          <p class="text-danger text-sm">{error()}</p>
        </Show>
        <div class="flex justify-end gap-2 mt-4">
          <button type="button" class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface" onClick={props.onClose}>Cancel</button>
          <button type="submit" class="px-3 py-1.5 text-sm rounded-md bg-accent text-bg font-medium hover:bg-accent-hover disabled:opacity-50" disabled={saving() || !title()}>
            {saving() ? "Creating..." : "Create"}
          </button>
        </div>
      </form>
    </div>
  );
}
