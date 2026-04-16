import express from "express";
import { ReaderClient } from "@vakra-dev/reader";

import {
  UnsafeScrapeTargetError,
  validateAndResolveScrapeURL,
} from "./security";

export const MAX_TIMEOUT_MS = 120_000; // 2 minutes cap
const READER_PROVIDER = "reader";

type ScrapePage = {
  markdown?: string;
  metadata?: {
    website?: Record<string, unknown>;
    duration?: number;
  };
};

type ScrapeResult = {
  data: ScrapePage[];
};

type ScrapeReader = {
  scrape(options: {
    urls: string[];
    formats: string[];
    onlyMainContent: boolean;
    removeAds: boolean;
    timeoutMs: number;
    maxRetries: number;
  }): Promise<ScrapeResult>;
};

type ScrapeURLValidator = (url: string) => Promise<string>;

type ScrapeErrorCode =
  | "invalid_request"
  | "blocked_target"
  | "timeout"
  | "network"
  | "empty_content"
  | "internal";

type ScrapeErrorBody = {
  error: string;
  code: ScrapeErrorCode;
  provider: typeof READER_PROVIDER;
  retryable: boolean;
};

let sharedReader: ScrapeReader | null = null;

function getReader(): ScrapeReader {
  if (!sharedReader) {
    sharedReader = new ReaderClient({
      verbose: process.env.NODE_ENV !== "production",
    });
  }

  return sharedReader;
}

export function createApp({
  reader,
  validateURL = validateAndResolveScrapeURL,
}: {
  reader?: ScrapeReader;
  validateURL?: ScrapeURLValidator;
} = {}) {
  const app = express();
  app.use(express.json());

  // Single URL scrape
  app.post("/scrape", async (req, res) => {
    const { url, timeout_ms } = req.body;

    if (!url) {
      writeScrapeError(res, 400, {
        error: "url is required",
        code: "invalid_request",
        provider: READER_PROVIDER,
        retryable: false,
      });
      return;
    }

    try {
      const safeURL = await validateURL(url);
      const result = await (reader ?? getReader()).scrape({
        urls: [safeURL],
        formats: ["markdown"],
        onlyMainContent: true,
        removeAds: true,
        timeoutMs: Math.min(timeout_ms || 30000, MAX_TIMEOUT_MS),
        maxRetries: 2,
      });

      const page = result.data[0];
      if (!page || !page.markdown) {
        writeScrapeError(res, 422, {
          error: "failed to extract content",
          code: "empty_content",
          provider: READER_PROVIDER,
          retryable: false,
        });
        return;
      }

      res.json({
        markdown: page.markdown,
        metadata: page.metadata?.website || {},
        duration_ms: page.metadata?.duration || 0,
      });
    } catch (err: unknown) {
      if (err instanceof UnsafeScrapeTargetError) {
        writeScrapeError(res, 400, {
          error: "url is not allowed",
          code: "blocked_target",
          provider: READER_PROVIDER,
          retryable: false,
        });
        return;
      }

      const classified = classifyScrapeFailure(err);
      writeScrapeError(res, classified.status, classified.body);
    }
  });

  // Health check
  app.get("/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  return app;
}

const app = createApp();

const port = parseInt(process.env.PORT || "3000", 10);

export const server =
  process.env.NODE_ENV === "test"
    ? null
    : app.listen(port, () => {
        console.log(`Reader service listening on :${port}`);
      });

export default app;

function writeScrapeError(res: express.Response, status: number, body: ScrapeErrorBody) {
  res.status(status).json(body);
}

function classifyScrapeFailure(err: unknown): { status: number; body: ScrapeErrorBody } {
  if (isTimeoutError(err)) {
    return {
      status: 504,
      body: {
        error: "reader request timed out",
        code: "timeout",
        provider: READER_PROVIDER,
        retryable: true,
      },
    };
  }

  if (isNetworkError(err)) {
    return {
      status: 502,
      body: {
        error: "reader upstream network failure",
        code: "network",
        provider: READER_PROVIDER,
        retryable: true,
      },
    };
  }

  return {
    status: 502,
    body: {
      error: err instanceof Error ? err.message : "reader upstream failure",
      code: "internal",
      provider: READER_PROVIDER,
      retryable: true,
    },
  };
}

function isTimeoutError(err: unknown): boolean {
  if (!(err instanceof Error)) {
    return false;
  }

  const message = err.message.toLowerCase();
  return (
    err.name === "AbortError" ||
    message.includes("timeout") ||
    message.includes("timed out") ||
    message.includes("deadline exceeded")
  );
}

function isNetworkError(err: unknown): boolean {
  if (!(err instanceof Error)) {
    return false;
  }

  const message = err.message.toLowerCase();
  return (
    message.includes("econnreset") ||
    message.includes("connection reset") ||
    message.includes("socket hang up") ||
    message.includes("fetch failed") ||
    message.includes("network") ||
    message.includes("dial tcp") ||
    message.includes("connect")
  );
}
