import test from "node:test";
import assert from "node:assert/strict";
import {
  accountIdFromToken,
  decodeBase64URL,
  isAllowedCodexEndpoint,
  isAllowedOpenRouterEndpoint,
  normalizeCodexUsage,
  normalizeOpenRouterCredits,
  normalizeResetCredits
} from "../local-status-server.mjs";

test("Codex endpoint allowlist matches only the read-only wham endpoints", () => {
  assert.equal(isAllowedCodexEndpoint("https://chatgpt.com/backend-api/wham/usage"), true);
  assert.equal(isAllowedCodexEndpoint("https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"), true);
  assert.equal(isAllowedCodexEndpoint("http://chatgpt.com/backend-api/wham/usage"), false);
  assert.equal(isAllowedCodexEndpoint("https://evil.chatgpt.com/backend-api/wham/usage"), false);
  assert.equal(isAllowedCodexEndpoint("https://chatgpt.com/backend-api/wham/usage?foo=bar"), false);
  assert.equal(isAllowedCodexEndpoint("https://chatgpt.com/backend-api/wham/usage/"), false);
});

test("OpenRouter endpoint allowlist is limited to credits", () => {
  assert.equal(isAllowedOpenRouterEndpoint("https://openrouter.ai/api/v1/credits"), true);
  assert.equal(isAllowedOpenRouterEndpoint("https://openrouter.ai/api/v1/credits?x=1"), false);
  assert.equal(isAllowedOpenRouterEndpoint("https://api.openrouter.ai/api/v1/credits"), false);
});

test("base64url decoding and Codex account fallback work", () => {
  assert.equal(decodeBase64URL("eyJhY2NvdW50IjoiYWNjdF8xMjMifQ"), '{"account":"acct_123"}');

  const payload = Buffer.from(JSON.stringify({
    "https://api.openai.com/auth": {
      chatgpt_account_id: "acct_from_jwt"
    }
  })).toString("base64url");

  assert.equal(accountIdFromToken(`header.${payload}.sig`, "acct_fallback"), "acct_from_jwt");
  assert.equal(accountIdFromToken("not-a-jwt", "acct_fallback"), "acct_fallback");
});

test("Codex usage normalizer derives remaining windows and reset dates", () => {
  const usage = normalizeCodexUsage({
    plan_type: "pro",
    rate_limit: {
      allowed: true,
      limit_reached: false,
      primary_window: {
        used_percent: 25,
        limit_window_seconds: 18_000,
        reset_after_seconds: 900,
        reset_at: 1_800_000_000_000
      },
      secondary_window: {
        used_percent: 80,
        limit_window_seconds: 604_800
      }
    }
  });

  assert.equal(usage.planType, "pro");
  assert.equal(usage.windows[0].title, "5h limit");
  assert.equal(usage.windows[0].remainingPercent, 75);
  assert.equal(usage.windows[1].title, "Weekly limit");
  assert.equal(usage.windows[1].remainingPercent, 20);
});

test("reset credits drop malformed rows and derive available count", () => {
  const resetCredits = normalizeResetCredits({
    credits: [
      { id: 123, status: "AVAILABLE", expires_at: "2026-07-11T21:13:00Z" },
      { status: "available" },
      { id: "credit-2", status: "redeemed" }
    ]
  });

  assert.deepEqual(resetCredits.credits.map((credit) => credit.id), ["123", "credit-2"]);
  assert.equal(resetCredits.availableCount, 1);
});

test("OpenRouter credits derive remaining and usage percentage", () => {
  const credits = normalizeOpenRouterCredits({
    data: {
      total_credits: 100.5,
      total_usage: 25.75
    }
  });

  assert.equal(credits.totalCredits, 100.5);
  assert.equal(credits.totalUsage, 25.75);
  assert.equal(credits.remainingCredits, 74.75);
  assert.equal(Math.round(credits.usagePercent), 26);
});
