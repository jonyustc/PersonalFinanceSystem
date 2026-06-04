import {
  clearAuthSession,
  getAccessToken,
  getRefreshToken,
  saveAuthTokens,
} from "@/services/token-store";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  "https://personalfinancesystem.onrender.com/api/v1";

type RequestOptions = RequestInit & {
  auth?: boolean;
};

export class ApiError extends Error {
  status: number;
  details: unknown;

  constructor(status: number, message: string, details?: unknown) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

let refreshPromise: Promise<string | null> | null = null;

function redirectToLogin() {
  if (typeof window !== "undefined" && window.location.pathname !== "/auth/login") {
    window.location.assign("/auth/login");
  }
}

async function refreshAccessToken() {
  const refreshToken = getRefreshToken();
  if (!refreshToken) return null;

  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
    })
      .then(async (response) => {
        if (!response.ok) return null;
        const tokens = (await response.json()) as {
          access_token: string;
          refresh_token: string;
        };
        saveAuthTokens(tokens);
        return tokens.access_token;
      })
      .catch(() => null)
      .finally(() => {
        refreshPromise = null;
      });
  }

  return refreshPromise;
}

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const request = async (token?: string | null) => {
    const headers = new Headers(options.headers);
    headers.set("Content-Type", "application/json");

    if (options.auth !== false && token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    return fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
    });
  };

  const token = options.auth !== false ? getAccessToken() : null;
  let response = await request(token);

  if (response.status === 401 && options.auth !== false && !path.startsWith("/auth/refresh")) {
    const nextToken = await refreshAccessToken();
    if (nextToken) {
      response = await request(nextToken);
    } else {
      clearAuthSession();
      redirectToLogin();
    }
  }

  if (!response.ok) {
    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = await response.text();
    }
    const message =
      typeof body === "object" && body && "detail" in body
        ? String(body.detail)
        : "Request failed";

    if (response.status === 401 && options.auth !== false) {
      clearAuthSession();
      redirectToLogin();
    }

    throw new ApiError(response.status, message, body);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}
