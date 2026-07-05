import { createReadStream, promises as fs } from "node:fs";
import { createServer } from "node:http";
import { request as httpsRequest } from "node:https";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(fileURLToPath(new URL(".", import.meta.url)));
const DEFAULT_PORT = Number.parseInt(process.env.PORT || "8787", 10);
const CODEX_HOME = join(process.env.HOME || "", ".codex");
const CODEX_USAGE_ENDPOINT = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_CREDITS_ENDPOINT = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits";
const OPENROUTER_CREDITS_ENDPOINT = "https://openrouter.ai/api/v1/credits";

const CODEX_ALLOWED_PATHS = new Set([
  "/backend-api/wham/usage",
  "/backend-api/wham/rate-limit-reset-credits"
]);

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".svg": "image/svg+xml"
};

export function isAllowedCodexEndpoint(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }

  return url.protocol === "https:"
    && url.hostname.toLowerCase() === "chatgpt.com"
    && (url.port === "" || url.port === "443")
    && url.username === ""
    && url.password === ""
    && url.search === ""
    && url.hash === ""
    && !url.href.endsWith("/")
    && CODEX_ALLOWED_PATHS.has(url.pathname);
}

export function isAllowedOpenRouterEndpoint(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }

  return url.protocol === "https:"
    && url.hostname.toLowerCase() === "openrouter.ai"
    && (url.port === "" || url.port === "443")
    && url.username === ""
    && url.password === ""
    && url.search === ""
    && url.hash === ""
    && url.pathname === "/api/v1/credits";
}

export function decodeBase64URL(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }

  try {
    const normalized = value
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(value.length / 4) * 4, "=");
    return Buffer.from(normalized, "base64").toString("utf8");
  } catch {
    return null;
  }
}

export function accountIdFromToken(token, fallback) {
  const parts = String(token || "").split(".");
  if (parts.length < 2) {
    return fallback || null;
  }

  try {
    const payload = JSON.parse(decodeBase64URL(parts[1]) || "{}");
    return payload?.["https://api.openai.com/auth"]?.chatgpt_account_id || fallback || null;
  } catch {
    return fallback || null;
  }
}

export function normalizeCodexUsage(response) {
  const rateLimit = response?.rate_limit || response?.rateLimit || {};
  const windows = [];
  const primary = rateLimit.primary_window || rateLimit.primaryWindow;
  const secondary = rateLimit.secondary_window || rateLimit.secondaryWindow;

  if (primary) {
    windows.push(normalizeCodexWindow(primary, "primary", rateLimit.limit_reached || rateLimit.limitReached));
  }
  if (secondary) {
    windows.push(normalizeCodexWindow(secondary, "secondary", rateLimit.limit_reached || rateLimit.limitReached));
  }

  return {
    planType: response?.plan_type || response?.planType || "Codex",
    allowed: rateLimit.allowed ?? null,
    limitReached: rateLimit.limit_reached ?? rateLimit.limitReached ?? null,
    fallbackResetCount: response?.rate_limit_reset_credits?.available_count
      ?? response?.rateLimitResetCredits?.availableCount
      ?? null,
    windows
  };
}

export function normalizeResetCredits(response) {
  const rows = Array.isArray(response?.credits) ? response.credits : [];
  const credits = rows
    .map((credit) => normalizeResetCredit(credit))
    .filter(Boolean)
    .sort((a, b) => {
      if (a.expiresAt && b.expiresAt) {
        return a.expiresAt.localeCompare(b.expiresAt);
      }
      if (a.expiresAt) return -1;
      if (b.expiresAt) return 1;
      return a.id.localeCompare(b.id);
    });

  return {
    availableCount: Number.isFinite(response?.available_count)
      ? response.available_count
      : credits.filter((credit) => credit.isAvailable).length,
    credits
  };
}

export function normalizeOpenRouterCredits(response) {
  const data = response?.data || {};
  const totalCredits = numberOrNull(data.total_credits);
  const totalUsage = numberOrNull(data.total_usage);
  const remainingCredits = totalCredits == null || totalUsage == null
    ? null
    : Math.max(0, totalCredits - totalUsage);
  const usagePercent = totalCredits && totalUsage != null
    ? clamp((totalUsage / totalCredits) * 100, 0, 100)
    : null;

  return {
    totalCredits,
    totalUsage,
    remainingCredits,
    usagePercent
  };
}

export async function readCodexAuth(codexHome = CODEX_HOME) {
  const authPath = join(codexHome, "auth.json");
  let raw;
  try {
    raw = await fs.readFile(authPath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      throw new StatusError(404, "Could not find Codex login. Open Codex Desktop and sign in first.");
    }
    throw error;
  }

  try {
    const auth = JSON.parse(raw);
    const accessToken = auth?.tokens?.access_token;
    if (!accessToken) {
      throw new Error("missing access token");
    }
    return {
      accessToken,
      accountId: accountIdFromToken(accessToken, auth?.tokens?.account_id)
    };
  } catch {
    throw new StatusError(422, "Could not read Codex login. Open Codex Desktop and sign in again.");
  }
}

export async function fetchCodexStatus({ codexHome = CODEX_HOME, fetchJSON = fetchJSONWithHTTPS } = {}) {
  const auth = await readCodexAuth(codexHome);
  const headers = {
    Authorization: `Bearer ${auth.accessToken}`,
    originator: "Codex Desktop",
    "OAI-Product-Sku": "CODEX",
    Accept: "application/json"
  };

  if (auth.accountId) {
    headers["ChatGPT-Account-Id"] = auth.accountId;
  }

  const [usageResult, creditsResult] = await Promise.allSettled([
    fetchJSON(CODEX_USAGE_ENDPOINT, { headers, allow: isAllowedCodexEndpoint }),
    fetchJSON(CODEX_CREDITS_ENDPOINT, { headers, allow: isAllowedCodexEndpoint })
  ]);

  const errors = [];
  const usage = usageResult.status === "fulfilled"
    ? normalizeCodexUsage(usageResult.value)
    : null;
  const resetCredits = creditsResult.status === "fulfilled"
    ? normalizeResetCredits(creditsResult.value)
    : null;

  if (usageResult.status === "rejected") {
    errors.push(statusErrorMessage("usage meters", usageResult.reason));
  }
  if (creditsResult.status === "rejected") {
    errors.push(statusErrorMessage("reset credits", creditsResult.reason));
  }

  if (!usage && !resetCredits) {
    throw new StatusError(502, errors.join(" ") || "Could not load Codex status.");
  }

  return {
    ok: errors.length === 0,
    provider: "codex",
    checkedAt: new Date().toISOString(),
    planType: usage?.planType || "Codex",
    allowed: usage?.allowed ?? null,
    limitReached: usage?.limitReached ?? null,
    windows: usage?.windows || [],
    resetCredits: resetCredits || {
      availableCount: usage?.fallbackResetCount || 0,
      credits: []
    },
    errors
  };
}

export async function fetchOpenRouterStatus(apiKey, { fetchJSON = fetchJSONWithHTTPS } = {}) {
  const key = String(apiKey || "").trim();
  if (!key) {
    throw new StatusError(400, "Paste an OpenRouter management API key to check credits.");
  }

  const response = await fetchJSON(OPENROUTER_CREDITS_ENDPOINT, {
    headers: {
      Authorization: `Bearer ${key}`,
      Accept: "application/json"
    },
    allow: isAllowedOpenRouterEndpoint
  });

  return {
    ok: true,
    provider: "openrouter",
    checkedAt: new Date().toISOString(),
    ...normalizeOpenRouterCredits(response)
  };
}

export function createDashisServer({ root = ROOT, port = DEFAULT_PORT } = {}) {
  const server = createServer(async (request, response) => {
    try {
      if (request.method === "GET" && request.url === "/api/status/codex") {
        return sendJSON(response, 200, await fetchCodexStatus());
      }

      if (request.method === "POST" && request.url === "/api/status/openrouter") {
        const body = await readRequestJSON(request);
        return sendJSON(response, 200, await fetchOpenRouterStatus(body?.apiKey));
      }

      if (request.url?.startsWith("/api/")) {
        return sendJSON(response, 404, { ok: false, error: "Unknown status endpoint." });
      }

      return serveStatic(request, response, root);
    } catch (error) {
      const status = error instanceof StatusError ? error.status : 500;
      const message = error instanceof StatusError
        ? error.message
        : "Dashis local status connector failed.";
      return sendJSON(response, status, { ok: false, error: message });
    }
  });

  return {
    server,
    listen() {
      server.listen(port, "127.0.0.1", () => {
        console.log(`Dashis local status connector listening on http://localhost:${port}/`);
      });
    }
  };
}

async function serveStatic(request, response, root) {
  const path = new URL(request.url || "/", "http://localhost");
  const requestedPath = path.pathname === "/" ? "/index.html" : path.pathname;
  const filePath = resolve(root, requestedPath.replace(/^\/+/, ""));
  const rootPrefix = root.endsWith(sep) ? root : `${root}${sep}`;

  if (filePath !== root && !filePath.startsWith(rootPrefix)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  try {
    const stat = await fs.stat(filePath);
    if (!stat.isFile()) {
      throw new Error("not a file");
    }
    response.writeHead(200, {
      "Content-Type": MIME_TYPES[extname(filePath)] || "application/octet-stream",
      "Cache-Control": "no-store"
    });
    createReadStream(filePath).pipe(response);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
  }
}

async function fetchJSONWithHTTPS(endpoint, { headers, allow }) {
  if (!allow(endpoint)) {
    throw new StatusError(403, "Endpoint is not allowed.");
  }

  return new Promise((resolvePromise, rejectPromise) => {
    const url = new URL(endpoint);
    const request = httpsRequest({
      protocol: url.protocol,
      hostname: url.hostname,
      path: url.pathname,
      method: "GET",
      headers,
      timeout: 20_000
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        const statusCode = response.statusCode || 0;
        const contentType = String(response.headers["content-type"] || "");

        if (statusCode === 429) {
          rejectPromise(new StatusError(429, "Remote endpoint rate-limited this status check."));
          return;
        }
        if (statusCode < 200 || statusCode >= 300) {
          rejectPromise(new StatusError(statusCode, `Remote endpoint returned HTTP ${statusCode}.`));
          return;
        }
        if (!body) {
          rejectPromise(new StatusError(502, "Remote endpoint returned an empty response."));
          return;
        }
        if (contentType && !contentType.toLowerCase().includes("json")) {
          rejectPromise(new StatusError(502, "Remote endpoint returned non-JSON content."));
          return;
        }

        try {
          resolvePromise(JSON.parse(body));
        } catch {
          rejectPromise(new StatusError(502, "Remote endpoint returned invalid JSON."));
        }
      });
    });

    request.on("timeout", () => {
      request.destroy(new StatusError(504, "Remote endpoint timed out."));
    });
    request.on("error", rejectPromise);
    request.end();
  });
}

async function readRequestJSON(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
    if (Buffer.concat(chunks).length > 16_384) {
      throw new StatusError(413, "Request body is too large.");
    }
  }

  if (chunks.length === 0) {
    return {};
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new StatusError(400, "Request body must be valid JSON.");
  }
}

function normalizeCodexWindow(window, fallbackId, limitReached) {
  const limitWindowSeconds = numberOrNull(window.limit_window_seconds ?? window.limitWindowSeconds);
  const usedPercent = clamp(numberOrNull(window.used_percent ?? window.usedPercent) ?? 0, 0, 100);
  const resetAfterSeconds = numberOrNull(window.reset_after_seconds ?? window.resetAfterSeconds);
  const resetAtRaw = numberOrNull(window.reset_at ?? window.resetAt);
  const resetAtSeconds = resetAtRaw && resetAtRaw > 10_000_000_000 ? resetAtRaw / 1000 : resetAtRaw;
  const title = fallbackId === "primary" || (limitWindowSeconds >= 14_400 && limitWindowSeconds <= 21_600)
    ? "5h limit"
    : fallbackId === "secondary" || (limitWindowSeconds >= 518_400 && limitWindowSeconds <= 864_000)
      ? "Weekly limit"
      : windowTitle(limitWindowSeconds || 0);

  return {
    id: fallbackId === "primary" ? "five-hour" : fallbackId === "secondary" ? "weekly" : fallbackId,
    title,
    usedPercent,
    remainingPercent: clamp(100 - usedPercent, 0, 100),
    limitWindowSeconds,
    resetAfterSeconds,
    resetAt: resetAtSeconds ? new Date(resetAtSeconds * 1000).toISOString() : null,
    limitReached: Boolean(limitReached)
  };
}

function normalizeResetCredit(credit) {
  const id = flexibleString(credit?.id);
  if (!id) {
    return null;
  }
  const status = flexibleString(credit?.status) || "unknown";
  return {
    id,
    resetType: flexibleString(credit?.reset_type ?? credit?.resetType) || "unknown",
    status,
    isAvailable: status.toLowerCase() === "available",
    expiresAt: flexibleString(credit?.expires_at ?? credit?.expiresAt),
    title: flexibleString(credit?.title) || "Codex reset credit"
  };
}

function flexibleString(value) {
  if (value == null) return null;
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  return null;
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function windowTitle(seconds) {
  if (seconds >= 86_400) {
    return `${Math.max(1, Math.floor(seconds / 86_400))}d limit`;
  }
  return `${Math.max(1, Math.floor(seconds / 3_600))}h limit`;
}

function statusErrorMessage(area, error) {
  const message = error instanceof Error ? error.message : "Unknown error.";
  return `Could not load ${area}. ${message}`;
}

function sendJSON(response, status, body) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(body));
}

export class StatusError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  createDashisServer().listen();
}
