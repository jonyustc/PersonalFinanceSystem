"use client";

import type { AuthResponse, User } from "@/types/api";

const ACCESS_TOKEN_KEY = "pf_access_token";
const REFRESH_TOKEN_KEY = "pf_refresh_token";
const USER_KEY = "pf_user";

export function saveAuthSession(auth: AuthResponse) {
  localStorage.setItem(ACCESS_TOKEN_KEY, auth.access_token);
  localStorage.setItem(REFRESH_TOKEN_KEY, auth.refresh_token);
  localStorage.setItem(USER_KEY, JSON.stringify(auth.user));
}

export function getAccessToken() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function getStoredUser(): User | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(USER_KEY);
  return raw ? (JSON.parse(raw) as User) : null;
}

export function clearAuthSession() {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}
