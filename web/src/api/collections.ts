import { api, libPath } from "./client";

export interface ZoteroCollection {
  key: string;
  version: number;
  library: { type: string; id: number };
  meta: { numCollections?: number; numItems?: number };
  data: {
    key: string;
    version: number;
    name: string;
    parentCollection?: string | false;
  };
}

export async function getCollections() {
  const { data } = await api<ZoteroCollection[]>(libPath("/collections"));
  return data;
}

export async function getCollection(key: string) {
  const { data } = await api<ZoteroCollection>(libPath(`/collections/${key}`));
  return data;
}

export async function createCollections(collections: { name: string; parentCollection?: string }[]) {
  const { data } = await api(libPath("/collections"), {
    method: "POST",
    body: JSON.stringify(collections),
  });
  return data;
}

export async function patchCollection(key: string, patch: Record<string, unknown>, version: number) {
  const { data } = await api<ZoteroCollection>(libPath(`/collections/${key}`), {
    method: "PATCH",
    body: JSON.stringify(patch),
    version,
  });
  return data;
}

export async function deleteCollection(key: string, version: number) {
  await api(libPath(`/collections/${key}`), {
    method: "DELETE",
    version,
  });
}
