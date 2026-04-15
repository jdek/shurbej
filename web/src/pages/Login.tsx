import { createSignal, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { login, verifyKey } from "../api/auth";
import { ApiError } from "../api/client";
import { setApiKey, setUserId } from "../lib/auth";

export default function Login() {
  const navigate = useNavigate();
  const [mode, setMode] = createSignal<"password" | "apikey">("password");
  const [username, setUsername] = createSignal("");
  const [password, setPassword] = createSignal("");
  const [key, setKey] = createSignal("");
  const [error, setError] = createSignal("");
  const [loading, setLoading] = createSignal(false);

  async function handlePassword(e: Event) {
    e.preventDefault();
    if (!username().trim() || !password()) return;
    setLoading(true);
    setError("");
    try {
      const result = await login(username().trim(), password());
      setUserId(result.userID);
      setApiKey(result.apiKey);
      navigate("/", { replace: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 429) {
        setError("Too many attempts. Wait a few minutes.");
      } else {
        setError("Invalid username or password");
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleApiKey(e: Event) {
    e.preventDefault();
    const k = key().trim();
    if (!k) return;
    setLoading(true);
    setError("");
    setApiKey(k);
    try {
      const info = await verifyKey();
      setUserId(info.userID);
      navigate("/", { replace: true });
    } catch {
      setApiKey(null);
      setError("Invalid API key");
    } finally {
      setLoading(false);
    }
  }

  const input = "w-full bg-bg border border-border rounded-md px-3 py-1.5 text-sm outline-none focus:border-accent";

  return (
    <div class="flex items-center justify-center h-screen bg-bg">
      <div class="bg-raised border border-border rounded-lg p-8 w-90">
        <h1 class="text-xl font-semibold text-center mb-6">Shurbey</h1>

        <div class="flex mb-5 border border-border rounded-md overflow-hidden text-sm">
          <button
            class="flex-1 py-1.5 transition-colors"
            classList={{
              "bg-accent text-bg": mode() === "password",
              "bg-raised text-dim hover:bg-surface": mode() !== "password",
            }}
            onClick={() => { setMode("password"); setError(""); }}
          >
            Login
          </button>
          <button
            class="flex-1 py-1.5 transition-colors"
            classList={{
              "bg-accent text-bg": mode() === "apikey",
              "bg-raised text-dim hover:bg-surface": mode() !== "apikey",
            }}
            onClick={() => { setMode("apikey"); setError(""); }}
          >
            API Key
          </button>
        </div>

        <Show when={mode() === "password"}>
          <form onSubmit={handlePassword}>
            <div class="mb-3">
              <label class="block text-xs text-dim mb-1">Username</label>
              <input
                type="text"
                value={username()}
                onInput={(e) => setUsername(e.currentTarget.value)}
                class={input}
                autofocus
              />
            </div>
            <div class="mb-4">
              <label class="block text-xs text-dim mb-1">Password</label>
              <input
                type="password"
                value={password()}
                onInput={(e) => setPassword(e.currentTarget.value)}
                class={input}
              />
            </div>
            <button
              class="w-full bg-accent text-bg font-medium py-1.5 rounded-md hover:bg-accent-hover disabled:opacity-50"
              type="submit"
              disabled={loading() || !username().trim() || !password()}
            >
              {loading() ? "Signing in..." : "Sign in"}
            </button>
          </form>
        </Show>

        <Show when={mode() === "apikey"}>
          <form onSubmit={handleApiKey}>
            <div class="mb-4">
              <label class="block text-xs text-dim mb-1">API Key</label>
              <input
                type="password"
                placeholder="Enter your API key"
                value={key()}
                onInput={(e) => setKey(e.currentTarget.value)}
                class={input}
                autofocus
              />
            </div>
            <button
              class="w-full bg-accent text-bg font-medium py-1.5 rounded-md hover:bg-accent-hover disabled:opacity-50"
              type="submit"
              disabled={loading() || !key().trim()}
            >
              {loading() ? "Verifying..." : "Sign in"}
            </button>
          </form>
        </Show>

        {error() && <p class="text-danger text-sm text-center mt-3">{error()}</p>}
      </div>
    </div>
  );
}
