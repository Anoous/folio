import express from "express";
import { ReaderClient } from "@vakra-dev/reader";

const app = express();
app.use(express.json());

const reader = new ReaderClient({
  verbose: process.env.NODE_ENV !== "production",
});

// SSRF protection: reject private/internal URLs
function isPrivateURL(rawURL: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(rawURL);
  } catch {
    return true; // unparseable URLs are rejected
  }

  const proto = parsed.protocol;
  if (proto !== "http:" && proto !== "https:") {
    return true;
  }

  const hostname = parsed.hostname.toLowerCase();

  // Block localhost variants
  if (
    hostname === "localhost" ||
    hostname === "[::1]" ||
    hostname.endsWith(".local")
  ) {
    return true;
  }

  // Block private/reserved IP ranges
  const parts = hostname.split(".").map(Number);
  if (parts.length === 4 && parts.every((n) => !isNaN(n))) {
    const [a, b] = parts;
    if (
      a === 127 || // loopback
      a === 10 || // 10.0.0.0/8
      (a === 172 && b >= 16 && b <= 31) || // 172.16.0.0/12
      (a === 192 && b === 168) || // 192.168.0.0/16
      (a === 169 && b === 254) || // link-local / cloud metadata
      a === 0 // 0.0.0.0/8
    ) {
      return true;
    }
  }

  return false;
}

const MAX_TIMEOUT_MS = 120_000; // 2 minutes cap

// Single URL scrape
app.post("/scrape", async (req, res) => {
  const { url, timeout_ms } = req.body;

  if (!url) {
    res.status(400).json({ error: "url is required" });
    return;
  }

  if (isPrivateURL(url)) {
    res.status(400).json({ error: "url is not allowed" });
    return;
  }

  try {
    const result = await reader.scrape({
      urls: [url],
      formats: ["markdown"],
      onlyMainContent: true,
      removeAds: true,
      timeoutMs: Math.min(timeout_ms || 30000, MAX_TIMEOUT_MS),
      maxRetries: 2,
    });

    const page = result.data[0];
    if (!page || !page.markdown) {
      res.status(422).json({ error: "failed to extract content" });
      return;
    }

    res.json({
      markdown: page.markdown,
      metadata: page.metadata?.website || {},
      duration_ms: page.metadata?.duration || 0,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "unknown error";
    res.status(500).json({ error: message });
  }
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

const port = parseInt(process.env.PORT || "3000", 10);

export const server = app.listen(port, () => {
  console.log(`Reader service listening on :${port}`);
});

export default app;
