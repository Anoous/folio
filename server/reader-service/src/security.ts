import dns from "node:dns/promises";
import { isIP } from "node:net";

export class UnsafeScrapeTargetError extends Error {
  constructor(message = "url is not allowed") {
    super(message);
    this.name = "UnsafeScrapeTargetError";
  }
}

export interface LookupAddress {
  address: string;
  family: number;
}

export interface RedirectProbeResponse {
  status: number;
  headers: {
    get(name: string): string | null;
  };
}

export interface URLSafetyOptions {
  resolver?: (hostname: string) => Promise<LookupAddress[]>;
  fetchImpl?: (input: string, init?: RequestInit) => Promise<RedirectProbeResponse>;
  maxRedirects?: number;
}

const MAX_REDIRECTS = 5;

const defaultResolver = (hostname: string) =>
  dns.lookup(hostname, { all: true, verbatim: true });

const defaultFetch = (input: string, init?: RequestInit) =>
  fetch(input, init) as Promise<RedirectProbeResponse>;

export async function validateAndResolveScrapeURL(
  rawURL: string,
  options: URLSafetyOptions = {},
): Promise<string> {
  const resolver = options.resolver ?? defaultResolver;
  const fetchImpl = options.fetchImpl ?? defaultFetch;
  const maxRedirects = options.maxRedirects ?? MAX_REDIRECTS;

  let current = rawURL;

  for (let hop = 0; hop <= maxRedirects; hop += 1) {
    const url = await assertSafeURL(current, resolver);

    let response: RedirectProbeResponse;
    try {
      response = await fetchImpl(url.toString(), {
        method: "GET",
        redirect: "manual",
      });
    } catch {
      return url.toString();
    }

    if (!isRedirectStatus(response.status)) {
      return url.toString();
    }

    const location = response.headers.get("location");
    if (!location) {
      throw new UnsafeScrapeTargetError("redirect target is missing");
    }

    current = new URL(location, url).toString();
  }

  throw new UnsafeScrapeTargetError("too many redirects");
}

export async function assertSafeURL(
  rawURL: string,
  resolver: (hostname: string) => Promise<LookupAddress[]> = defaultResolver,
): Promise<URL> {
  let url: URL;
  try {
    url = new URL(rawURL);
  } catch {
    throw new UnsafeScrapeTargetError();
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new UnsafeScrapeTargetError();
  }

  const hostname = normalizeHostname(url.hostname);
  if (isBlockedHostname(hostname)) {
    throw new UnsafeScrapeTargetError();
  }

  const literalFamily = isIP(hostname);
  if (literalFamily !== 0) {
    if (isDisallowedIPAddress(hostname)) {
      throw new UnsafeScrapeTargetError();
    }
    return url;
  }

  let addresses: LookupAddress[];
  try {
    addresses = await resolver(hostname);
  } catch {
    throw new UnsafeScrapeTargetError("hostname could not be resolved");
  }

  if (!addresses.length) {
    throw new UnsafeScrapeTargetError("hostname could not be resolved");
  }

  if (
    addresses.some((entry) =>
      isDisallowedIPAddress(entry.address, { allowBenchmarkProxy: true }),
    )
  ) {
    throw new UnsafeScrapeTargetError();
  }

  return url;
}

export function isBlockedHostname(hostname: string): boolean {
  const normalized = normalizeHostname(hostname);
  return (
    normalized === "localhost" ||
    normalized.endsWith(".localhost") ||
    normalized.endsWith(".local")
  );
}

export function isDisallowedIPAddress(
  address: string,
  options: { allowBenchmarkProxy?: boolean } = {},
): boolean {
  const normalized = address.trim().toLowerCase();

  if (normalized.startsWith("::ffff:")) {
    return isDisallowedIPv4(normalized.slice(7), options);
  }

  const family = isIP(normalized);
  if (family === 4) {
    return isDisallowedIPv4(normalized, options);
  }
  if (family === 6) {
    return isDisallowedIPv6(normalized);
  }

  return true;
}

function normalizeHostname(hostname: string): string {
  return hostname
    .trim()
    .toLowerCase()
    .replace(/^\[(.*)\]$/, "$1")
    .replace(/\.$/, "");
}

function isRedirectStatus(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function isDisallowedIPv4(
  address: string,
  options: { allowBenchmarkProxy?: boolean },
): boolean {
  const parts = address.split(".").map((part) => Number.parseInt(part, 10));
  if (parts.length !== 4 || parts.some((part) => Number.isNaN(part) || part < 0 || part > 255)) {
    return true;
  }

  const [a, b] = parts;

  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 0) ||
    (a === 192 && b === 168) ||
    (!options.allowBenchmarkProxy && a === 198 && (b === 18 || b === 19)) ||
    a >= 224
  );
}

function isDisallowedIPv6(address: string): boolean {
  if (address === "::" || address === "::1") {
    return true;
  }

  const normalized = address.toLowerCase();
  const firstHextet = normalized.split(":", 1)[0];

  if (firstHextet === "") {
    return false;
  }

  if (firstHextet.startsWith("fc") || firstHextet.startsWith("fd")) {
    return true;
  }

  if (firstHextet.startsWith("fe")) {
    const thirdNibble = firstHextet[2];
    if (thirdNibble === "8" || thirdNibble === "9" || thirdNibble === "a" || thirdNibble === "b") {
      return true;
    }
  }

  if (firstHextet.startsWith("ff")) {
    return true;
  }

  return false;
}
