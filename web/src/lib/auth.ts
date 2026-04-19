import { createSignal } from "solid-js";
import { clearLibraries } from "./library";

const STORAGE_KEY = "shurbej_api_key";
const USER_ID_KEY = "shurbej_user_id";

const stored = localStorage.getItem(STORAGE_KEY);
const storedUserId = localStorage.getItem(USER_ID_KEY);

const [apiKey, setApiKeyRaw] = createSignal<string | null>(stored);
const [userId, setUserIdRaw] = createSignal<number | null>(
  storedUserId ? parseInt(storedUserId, 10) : null
);

export function setApiKey(key: string | null) {
  if (key) {
    localStorage.setItem(STORAGE_KEY, key);
  } else {
    localStorage.removeItem(STORAGE_KEY);
  }
  setApiKeyRaw(key);
}

export function setUserId(id: number | null) {
  if (id !== null) {
    localStorage.setItem(USER_ID_KEY, String(id));
  } else {
    localStorage.removeItem(USER_ID_KEY);
  }
  setUserIdRaw(id);
}

export function logout() {
  setApiKey(null);
  setUserId(null);
  clearLibraries();
}

export { apiKey, userId };
