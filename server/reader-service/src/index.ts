import express from "express";
import { ReaderClient } from "@vakra-dev/reader";

const app = express();
app.use(express.json());

const reader = new ReaderClient({
  verbose: process.env.NODE_ENV !== "production",
});

// Single URL scrape
app.post("/scrape", async (req, res) => {
  const { url, timeout_ms } = req.body;

  if (!url) {
    res.status(400).json({ error: "url is required" });
    return;
  }

  try {
    const result = await reader.scrape({
      urls: [url],
      formats: ["markdown"],
      onlyMainContent: true,
      removeAds: true,
      timeoutMs: timeout_ms || 30000,
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
