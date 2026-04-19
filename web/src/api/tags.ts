import { api, libPath } from "./client";

export interface ZoteroTag {
  tag: string;
  meta: { type: number; numItems: number };
}

export async function getTags() {
  const { data } = await api<ZoteroTag[]>(libPath("/tags"));
  return data;
}

export async function deleteTags(tags: string[]) {
  const param = tags.map(encodeURIComponent).join("||");
  await api(libPath(`/tags?tag=${param}`), { method: "DELETE" });
}
