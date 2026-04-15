import { api, userPath } from "./client";

export interface ZoteroTag {
  tag: string;
  meta: { type: number; numItems: number };
}

export async function getTags() {
  const { data } = await api<ZoteroTag[]>(userPath("/tags"));
  return data;
}

export async function deleteTags(tags: string[]) {
  const param = tags.map(encodeURIComponent).join("||");
  await api(userPath(`/tags?tag=${param}`), { method: "DELETE" });
}
