"use client";

import type { AuthResponse, User } from "@/types/api";

const ACCESS_TOKEN_KEY = "pf_access_token";
const REFRESH_TOKEN_KEY = "pf_refresh_token";
const USER_KEY = "pf_user";

export function saveAuthSession(auth: AuthResponse) {
  if (typeof window === "undefined") return;
  localStorage.setItem(ACCESS_TOKEN_KEY, auth.access_token);
  localStorage.setItem(REFRESH_TOKEN_KEY, auth.refresh_token);
  localStorage.setItem(USER_KEY, JSON.stringify(auth.user));
}

export function saveAuthTokens(tokens: Pick<AuthResponse, "access_token" | "refresh_token">) {
  if (typeof window === "undefined") return;
  localStorage.setItem(ACCESS_TOKEN_KEY, tokens.access_token);
  // Never overwrite a working refresh token with a missing one — the old
  // token stays valid server-side, so keeping it preserves the session.
  if (tokens.refresh_token) {
    localStorage.setItem(REFRESH_TOKEN_KEY, tokens.refresh_token);
  }
}

export function getAccessToken() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function getRefreshToken() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

export function getStoredUser(): User | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(USER_KEY);
  return raw ? (JSON.parse(raw) as User) : null;
}

export function clearAuthSession() {
  if (typeof window === "undefined") return;
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}
