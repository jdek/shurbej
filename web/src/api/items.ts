import { api, libPath } from "./client";

export interface ZoteroItem {
  key: string;
  version: number;
  library: { type: string; id: number };
  meta: { numChildren?: number };
  data: Record<string, unknown> & {
    key: string;
    version: number;
    itemType: string;
    title?: string;
    name?: string;
    parentItem?: string;
    creators?: { creatorType: string; firstName?: string; lastName?: string; name?: string }[];
    tags?: { tag: string; type?: number }[];
    collections?: string[];
    dateAdded?: string;
    dateModified?: string;
    deleted?: boolean;
  };
}

export interface ListParams {
  sort?: string;
  direction?: "asc" | "desc";
  limit?: number;
  start?: number;
  since?: number;
  q?: string;
  qmode?: string;
  tag?: string;
  itemType?: string;
  format?: "json" | "keys" | "versions";
  includeTrashed?: boolean;
  itemKey?: string;
  collectionKey?: string;
}

function qs(params: ListParams): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== "") {
      p.set(k, String(v));
    }
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export async function getItems(params: ListParams = {}) {
  const { data, headers } = await api<ZoteroItem[]>(
    libPath(`/items${qs(params)}`)
  );
  return {
    items: data,
    totalResults: parseInt(headers.get("Total-Results") || "0", 10),
    libraryVersion: parseInt(headers.get("Last-Modified-Version") || "0", 10),
  };
}

export async function getTopItems(params: ListParams = {}) {
  const { data, headers } = await api<ZoteroItem[]>(
    libPath(`/items/top${qs(params)}`)
  );
  return {
    items: data,
    totalResults: parseInt(headers.get("Total-Results") || "0", 10),
    libraryVersion: parseInt(headers.get("Last-Modified-Version") || "0", 10),
  };
}

export async function getItem(key: string) {
  const { data } = await api<ZoteroItem>(libPath(`/items/${key}`));
  return data;
}

export async function getChildren(key: string) {
  const { data } = await api<ZoteroItem[]>(libPath(`/items/${key}/children`));
  return data;
}

export async function getTrashItems(params: ListParams = {}) {
  const { data, headers } = await api<ZoteroItem[]>(
    libPath(`/items/trash${qs(params)}`)
  );
  return {
    items: data,
    totalResults: parseInt(headers.get("Total-Results") || "0", 10),
    libraryVersion: parseInt(headers.get("Last-Modified-Version") || "0", 10),
  };
}

export async function createItems(items: Record<string, unknown>[]) {
  const { data } = await api(libPath("/items"), {
    method: "POST",
    body: JSON.stringify(items),
  });
  return data;
}

export async function patchItem(key: string, patch: Record<string, unknown>, version: number) {
  const { data } = await api<ZoteroItem>(libPath(`/items/${key}`), {
    method: "PATCH",
    body: JSON.stringify(patch),
    version,
  });
  return data;
}

export async function deleteItem(key: string, version: number) {
  await api(libPath(`/items/${key}`), {
    method: "DELETE",
    version,
  });
}

export async function getItemTemplate(itemType: string) {
  const { data } = await api<Record<string, unknown>>(`/items/new?itemType=${itemType}`);
  return data;
}

export async function getItemTypes() {
  const { data } = await api<{ itemType: string; localized: string }[]>("/itemTypes");
  return data;
}
