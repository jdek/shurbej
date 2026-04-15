import { api } from "./client";

export interface KeyInfo {
  key: string;
  userID: number;
  username: string;
  access: Record<string, unknown>;
}

export interface LoginResult {
  apiKey: string;
  userID: number;
  username: string;
}

export async function verifyKey() {
  const { data } = await api<KeyInfo>("/keys/current");
  return data;
}

export async function login(username: string, password: string) {
  const { data } = await api<LoginResult>("/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
  return data;
}

export async function revokeKey() {
  await api("/keys/current", { method: "DELETE" });
}
