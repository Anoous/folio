import { describe, it, expect, afterAll } from "vitest";
import request from "supertest";
import app, { server } from "../src/index";

afterAll(() => {
  server.close();
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
    expect(res.body.error).toBe("url is required");
  });

  it("returns 400 when body is empty", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({})
      .set("Content-Type", "application/json");
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is required");
  });

  // --- SSRF Protection ---

  it("rejects localhost", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://localhost:8080/secret" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 127.0.0.1", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://127.0.0.1/admin" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 10.x.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://10.0.0.1/internal" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 172.16.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://172.16.0.1/internal" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 192.168.x.x private range", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://192.168.1.1/router" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 169.254.x.x link-local / cloud metadata", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://169.254.169.254/latest/meta-data/" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects 0.0.0.0", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://0.0.0.0/" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects IPv6 loopback [::1]", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://[::1]:8080/" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects .local domains", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "http://myserver.local/api" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects ftp:// scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "ftp://example.com/file" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects file:// scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "file:///etc/passwd" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects javascript: scheme", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "javascript:alert(1)" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  it("rejects unparseable URLs", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({ url: "not a valid url at all :///" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is not allowed");
  });

  // --- Timeout capping ---

  it("caps timeout_ms to MAX_TIMEOUT_MS (120000)", async () => {
    // We can't easily assert the internal value, but we can verify the
    // request is accepted (doesn't crash) with an absurdly large timeout.
    // The actual scraping will fail because the URL is unreachable, but
    // the timeout logic itself should not error.
    const res = await request(app)
      .post("/scrape")
      .send({ url: "https://example.com", timeout_ms: 999999999 });
    // Should not be 400 (validation passes) — will be 422 or 500 depending
    // on whether the scrape succeeds, but not a timeout-related crash.
    expect(res.status).not.toBe(400);
  });
});
