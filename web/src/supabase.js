// Minimal client for Supabase Auth (GoTrue) and the REST API (PostgREST), like SupabaseClient.swift.
// Signs in to the same accounts as the app.

import { SUPABASE_ANON_KEY, SUPABASE_URL } from "../config.js";

export const isConfigured = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

export class SupabaseError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function request(path, { method = "GET", query = {}, body, token, headers = {} } = {}) {
  const url = new URL(path, SUPABASE_URL.replace(/\/?$/, "/"));
  for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        apikey: SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new SupabaseError(0, "Offline. Changes will sync when you are back online.");
  }
  const text = await response.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {}
  if (!response.ok) {
    const message = ["error_description", "msg", "message", "error"].map((k) => json[k]).find((m) => typeof m === "string" && m);
    throw new SupabaseError(response.status, message ?? `Server error (${response.status}).`);
  }
  return json;
}

function sessionFrom(json) {
  if (!json.access_token || !json.refresh_token || !json.user?.id) return null;
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000,
    userId: json.user.id,
    email: json.user.email ?? "",
  };
}

const unexpected = () => new SupabaseError(0, "Unexpected response from the server.");

// Auth

/** Creates an account. Returns null when the email address must be confirmed first. */
export async function signUp(email, password) {
  const json = await request("auth/v1/signup", {
    method: "POST", body: { email, password },
    query: { redirect_to: location.origin + location.pathname },
  });
  return sessionFrom(json);
}

export async function signIn(email, password) {
  const json = await request("auth/v1/token", { method: "POST", query: { grant_type: "password" }, body: { email, password } });
  return sessionFrom(json) ?? Promise.reject(unexpected());
}

export async function refresh(session) {
  const json = await request("auth/v1/token", {
    method: "POST", query: { grant_type: "refresh_token" }, body: { refresh_token: session.refreshToken },
  });
  return sessionFrom(json) ?? Promise.reject(unexpected());
}

export async function signOut(session) {
  await request("auth/v1/logout", { method: "POST", body: {}, token: session.accessToken }).catch(() => {});
}

/** The session in a confirmation or sign-in link (#access_token=…&refresh_token=…), if the page was opened from one. */
export async function sessionFromLink() {
  const params = new URLSearchParams(location.hash.slice(1));
  const access = params.get("access_token");
  const refreshToken = params.get("refresh_token");
  if (!access || !refreshToken) return null;
  history.replaceState(null, "", location.pathname + location.search + "#/today");
  const user = await request("auth/v1/user", { token: access });
  return sessionFrom({ access_token: access, refresh_token: refreshToken, expires_in: Number(params.get("expires_in")) || 3600, user });
}

// REST

/** GET rows of a table. `query` holds PostgREST filters, e.g. { updated_at: "gt.…" }. */
export const select = (table, query, token) => request(`rest/v1/${table}`, { query, token });

/** Inserts rows, updating (or, with `ignoreDuplicates`, keeping) rows whose primary key already exists. */
export async function upsert(table, rows, onConflict, token, ignoreDuplicates = false) {
  await request(`rest/v1/${table}`, {
    method: "POST", query: { on_conflict: onConflict }, body: rows, token,
    headers: { Prefer: `resolution=${ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"},return=minimal` },
  });
}

export async function rpc(fn, token) {
  await request(`rest/v1/rpc/${fn}`, { method: "POST", body: {}, token });
}
