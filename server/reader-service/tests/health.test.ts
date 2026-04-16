import { beforeEach, describe, expect, it, vi } from "vitest";
import request from "supertest";
import { createApp, MAX_TIMEOUT_MS } from "../src/index";
import { validateAndResolveScrapeURL } from "../src/security";

const scrapeMock = vi.fn();

let app = createApp();

beforeEach(() => {
  scrapeMock.mockReset();
  scrapeMock.mockResolvedValue({
    data: [
      {
        markdown: "# Example",
        metadata: {
          website: { name: "Example" },
          duration: 12,
        },
      },
    ],
  });

  app = createApp({
    reader: {
      scrape: scrapeMock,
    },
    validateURL: async (url) => {
      if (url === "https://example.com") {
        return url;
      }

      return validateAndResolveScrapeURL(url);
    },
  });
});

describe("GET /health", () => {
  it("returns status ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok" });
  });
});

describe("POST /scrape", () => {
  // --- Validation ---

  it("returns 400 when url is missing", async () => {
    const res = await request(app).post("/scrape").send({});
    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "url is required",
      code: "invalid_request",
      provider: "reader",
      retryable: false,
    });
  });

  it("returns 400 when body is empty", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({})
      .set("Content-Type", "application/json");
    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "url is required",
      code: "invalid_request",
      provider: "reader",
      retryable: false,
    });
  });

  // --- SSRF Protection ---

  it("rejects localhost", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://localhost:8080/secret" });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "url is not allowed",
      code: "blocked_target",
      provider: "reader",
      retryable: false,
    });
  });

  it("rejects 127.0.0.1", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://127.0.0.1/admin" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects 10.x.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://10.0.0.1/internal" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects 172.16.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://172.16.0.1/internal" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects 192.168.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://192.168.1.1/router" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects 169.254.x.x link-local / cloud metadata", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://169.254.169.254/latest/meta-data/" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects 0.0.0.0", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://0.0.0.0/" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects IPv6 loopback [::1]", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://[::1]:8080/" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects .local domains", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://myserver.local/api" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects ftp:// scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "ftp://example.com/file" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects file:// scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "file:///etc/passwd" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects javascript: scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "javascript:alert(1)" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("rejects unparseable URLs", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "not a valid url at all :///" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("blocked_target");
  });

  it("returns 422 with structured contract when extraction returns no markdown", async () => {
    scrapeMock.mockResolvedValueOnce({
      data: [{ markdown: "", metadata: { duration: 3 } }],
    });

    const res = await request(app)
      .post("/scrape")
      .send({ url: "https://example.com" });

    expect(res.status).toBe(422);
    expect(res.body).toEqual({
      error: "failed to extract content",
      code: "empty_content",
      provider: "reader",
      retryable: false,
    });
  });

  it("returns 504 with structured contract on timeout-like upstream failures", async () => {
    scrapeMock.mockRejectedValueOnce(new Error("request timed out"));

    const res = await request(app)
      .post("/scrape")
      .send({ url: "https://example.com" });

    expect(res.status).toBe(504);
    expect(res.body).toEqual({
      error: "reader request timed out",
      code: "timeout",
      provider: "reader",
      retryable: true,
    });
  });

  it("returns 502 with structured contract on network-like upstream failures", async () => {
    scrapeMock.mockRejectedValueOnce(new Error("fetch failed: ECONNRESET"));

    const res = await request(app)
      .post("/scrape")
      .send({ url: "https://example.com" });

    expect(res.status).toBe(502);
    expect(res.body).toEqual({
      error: "reader upstream network failure",
      code: "network",
      provider: "reader",
      retryable: true,
    });
  });

  // --- Timeout capping ---

  it("caps timeout_ms to MAX_TIMEOUT_MS (120000)", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "https://example.com", timeout_ms: 999999999 });

    expect(res.status).toBe(200);
    expect(scrapeMock).toHaveBeenCalledWith(
      expect.objectContaining({
        timeoutMs: MAX_TIMEOUT_MS,
      }),
    );
  });
});
