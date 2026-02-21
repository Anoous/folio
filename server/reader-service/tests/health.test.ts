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
  it("returns 400 when url is missing", async () => {
    const res = await request(app)
      .post("/scrape")
      .send({});
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("url is required");
  });
});
