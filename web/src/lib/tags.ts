import { createSignal } from "solid-js";

// Persisted tag colors: { [tag]: color }
const COLORS_KEY = "shurbey_tag_colors";
const stored = localStorage.getItem(COLORS_KEY);
const [tagColors, setTagColorsRaw] = createSignal<Record<string, string>>(
  stored ? JSON.parse(stored) : {}
);

export function setTagColor(tag: string, color: string) {
  const next = { ...tagColors(), [tag]: color };
  localStorage.setItem(COLORS_KEY, JSON.stringify(next));
  setTagColorsRaw(next);
}

export function removeTagColor(tag: string) {
  const next = { ...tagColors() };
  delete next[tag];
  localStorage.setItem(COLORS_KEY, JSON.stringify(next));
  setTagColorsRaw(next);
}

export { tagColors };

// Active tag filter selection
const [selectedTags, setSelectedTags] = createSignal<string[]>([]);

export function toggleTag(tag: string) {
  const current = selectedTags();
  if (current.includes(tag)) {
    setSelectedTags(current.filter((t) => t !== tag));
  } else {
    setSelectedTags([...current, tag]);
  }
}

export function clearTags() {
  setSelectedTags([]);
}

export { selectedTags };
