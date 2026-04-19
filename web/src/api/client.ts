import { apiKey, userId } from "../lib/auth";
import { currentLibrary } from "../lib/library";

// In dev, Vite proxies /api/* → backend. In prod, same origin serves both.
const BASE = import.meta.env.DEV ? "/api" : "";

export class ApiError extends Error {
  status: number;
  body: unknown;
  constructor(status: number, body: unknown) {
    super(`API error ${status}`);
    this.status = status;
    this.body = body;
  }
}

export async function api<T = unknown>(
  path: string,
  opts: RequestInit & { version?: number } = {},
): Promise<{ data: T; headers: Headers }> {
  const key = apiKey();
  const headers = new Headers(opts.headers);
  headers.set("Zotero-API-Version", "3");
  if (key) headers.set("Zotero-API-Key", key);
  if (!headers.has("Content-Type") && opts.body && typeof opts.body === "string") {
    headers.set("Content-Type", "application/json");
  }
  if (opts.version !== undefined) {
    headers.set("If-Unmodified-Since-Version", String(opts.version));
  }

  const res = await fetch(`${BASE}${path}`, { ...opts, headers });
  if (!res.ok) {
    const body = await res.text().catch(() => null);
    throw new ApiError(res.status, body);
  }

  const ct = res.headers.get("content-type") || "";
  const data = ct.includes("json") ? await res.json() : await res.text();
  return { data: data as T, headers: res.headers };
}

/** Path scoped to the authenticated user — use for endpoints that are always
 * user-scoped regardless of the active library (e.g. /users/:id/groups). */
export function userPath(path: string) {
  const uid = userId();
  return `/users/${uid}${path}`;
}

/** Path scoped to the currently-selected library. Emits `/users/:id...` or
 * `/groups/:id...` based on the library switcher. */
export function libPath(path: string) {
  const lib = currentLibrary();
  const prefix = lib.type === "user" ? "/users" : "/groups";
  return `${prefix}/${lib.id}${path}`;
}
