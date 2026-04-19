import { api, userPath } from "./client";

export interface ZoteroGroup {
  id: number;
  version: number;
  data: {
    id: number;
    version: number;
    name: string;
    owner: number;
    type: "Private" | "PublicClosed" | "PublicOpen";
    description?: string;
    url?: string;
    hasImage?: boolean;
    libraryEditing?: "members" | "admins";
    libraryReading?: "members" | "all";
    fileEditing?: "members" | "admins" | "none";
  };
}

/** Fetch the groups the authenticated user is a member of. */
export async function getGroups(): Promise<ZoteroGroup[]> {
  const { data } = await api<ZoteroGroup[]>(userPath("/groups"));
  return data;
}
