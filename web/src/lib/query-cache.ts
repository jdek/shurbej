import { createSignal, createEffect, on, untrack, type Accessor } from "solid-js";

/**
 * Stale-while-revalidate cache for API data.
 * Shows cached data instantly, refetches in background.
 */

interface CacheEntry<T> {
  data: T;
  timestamp: number;
}

const cache: Map<string, CacheEntry<unknown>> = new Map();
const inflight: Map<string, Promise<unknown>> = new Map();

const STALE_MS = 30_000; // 30s

export function createCachedResource<T, K extends string>(
  source: Accessor<K>,
  fetcher: (key: K) => Promise<T>,
): [Accessor<T | undefined>, { loading: Accessor<boolean>; refetch: () => void }] {
  const [data, setData] = createSignal<T | undefined>(undefined);
  const [loading, setLoading] = createSignal(false);

  let currentKey: string | null = null;

  async function doFetch(key: string): Promise<T> {
    let promise = inflight.get(key) as Promise<T> | undefined;
    if (!promise) {
      promise = fetcher(key as K);
      inflight.set(key, promise);
    }
    try {
      const result = await promise;
      cache.set(key, { data: result, timestamp: Date.now() });
      // Only update if this is still the current key
      if (currentKey === key) {
        setData(() => result);
      }
      return result;
    } finally {
      inflight.delete(key);
    }
  }

  function load(key: string) {
    if (key === currentKey) return;
    currentKey = key;

    const cached = cache.get(key) as CacheEntry<T> | undefined;
    if (cached) {
      setData(() => cached.data);
      if (Date.now() - cached.timestamp > STALE_MS) {
        doFetch(key);
      }
    } else {
      setData(() => undefined);
      setLoading(true);
      doFetch(key).finally(() => {
        if (currentKey === key) setLoading(false);
      });
    }
  }

  // Initial load
  const initialKey = untrack(source);
  if (initialKey) load(initialKey);

  // React to key changes
  createEffect(on(source, (key) => {
    if (key) load(key);
  }, { defer: true }));

  function refetch() {
    const key = untrack(source);
    if (!key) return;
    currentKey = null; // force reload
    setLoading(true);
    load(key);
  }

  return [data as Accessor<T | undefined>, { loading, refetch }];
}

export function invalidatePrefix(prefix: string) {
  for (const key of cache.keys()) {
    if (key.startsWith(prefix)) cache.delete(key);
  }
}

export function invalidate(key: string) {
  cache.delete(key);
}

/** Drop every cached entry. Call when the active library changes so that
 * item / collection / tag resources refetch against the new library. */
export function invalidateAll() {
  cache.clear();
  inflight.clear();
}
