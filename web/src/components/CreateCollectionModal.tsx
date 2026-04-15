import { createSignal, Show } from "solid-js";
import { createCollections } from "../api/collections";

export default function CreateCollectionModal(props: {
  parentKey?: string;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [name, setName] = createSignal("");
  const [saving, setSaving] = createSignal(false);
  const [error, setError] = createSignal("");

  async function handleSubmit(e: Event) {
    e.preventDefault();
    if (!name().trim()) return;
    setSaving(true);
    setError("");
    try {
      const payload: { name: string; parentCollection?: string } = { name: name().trim() };
      if (props.parentKey) payload.parentCollection = props.parentKey;
      await createCollections([payload]);
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
      <form class="bg-raised border border-border rounded-lg p-6 w-[400px]" onSubmit={handleSubmit}>
        <h2 class="text-base font-semibold mb-4">New Collection</h2>
        <div class="mb-3">
          <label class="block text-xs text-dim mb-1">Name</label>
          <input type="text" class={input} value={name()} onInput={(e) => setName(e.currentTarget.value)} autofocus />
        </div>
        <Show when={error()}>
          <p class="text-danger text-sm">{error()}</p>
        </Show>
        <div class="flex justify-end gap-2 mt-4">
          <button type="button" class="px-3 py-1.5 text-sm border border-border rounded-md bg-raised hover:bg-surface" onClick={props.onClose}>Cancel</button>
          <button type="submit" class="px-3 py-1.5 text-sm rounded-md bg-accent text-bg font-medium hover:bg-accent-hover disabled:opacity-50" disabled={saving() || !name().trim()}>
            {saving() ? "Creating..." : "Create"}
          </button>
        </div>
      </form>
    </div>
  );
}
