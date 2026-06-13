"use client";

import { apiRequest } from "@/services/api";
import { clearAuthSession, saveAuthSession } from "@/services/token-store";
import type { AuthResponse, LoginPayload, RegisterPayload, User } from "@/types/api";

export async function login(payload: LoginPayload) {
  const auth = await apiRequest<AuthResponse>("/auth/login", {
    method: "POST",
    auth: false,
    body: JSON.stringify(payload)
  });
  saveAuthSession(auth);
  return auth;
}

export async function loginWithGoogle(idToken: string) {
  const auth = await apiRequest<AuthResponse>("/auth/google", {
    method: "POST",
    auth: false,
    body: JSON.stringify({ id_token: idToken })
  });
  saveAuthSession(auth);
  return auth;
}

export async function register(payload: RegisterPayload) {
  const auth = await apiRequest<AuthResponse>("/auth/register", {
    method: "POST",
    auth: false,
    body: JSON.stringify(payload)
  });
  saveAuthSession(auth);
  return auth;
}

export async function getMe() {
  return apiRequest<User>("/auth/me");
}

export function logout() {
  clearAuthSession();
}
