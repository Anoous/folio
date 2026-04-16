import { describe, expect, it } from "vitest";

import {
  UnsafeScrapeTargetError,
  isDisallowedIPAddress,
  validateAndResolveScrapeURL,
} from "../src/security";

describe("isDisallowedIPAddress", () => {
  it("rejects private and reserved IPv4 ranges", () => {
    expect(isDisallowedIPAddress("127.0.0.1")).toBe(true);
    expect(isDisallowedIPAddress("10.0.0.8")).toBe(true);
    expect(isDisallowedIPAddress("169.254.169.254")).toBe(true);
    expect(isDisallowedIPAddress("192.168.1.1")).toBe(true);
    expect(isDisallowedIPAddress("198.18.0.20")).toBe(true);
  });

  it("rejects loopback, link-local, ula, and mapped IPv6 addresses", () => {
    expect(isDisallowedIPAddress("::1")).toBe(true);
    expect(isDisallowedIPAddress("fe80::1")).toBe(true);
    expect(isDisallowedIPAddress("fc00::1")).toBe(true);
    expect(isDisallowedIPAddress("::ffff:127.0.0.1")).toBe(true);
  });

  it("allows public IPv4 and IPv6 addresses", () => {
    expect(isDisallowedIPAddress("8.8.8.8")).toBe(false);
    expect(isDisallowedIPAddress("2606:4700:4700::1111")).toBe(false);
  });
});

describe("validateAndResolveScrapeURL", () => {
  it("rejects hostnames that resolve to loopback", async () => {
    await expect(
      validateAndResolveScrapeURL("https://folio.example/article", {
        resolver: async () => [{ address: "127.0.0.1", family: 4 }],
        fetchImpl: async () => ({
          status: 200,
          headers: { get: () => null },
        }),
      }),
    ).rejects.toBeInstanceOf(UnsafeScrapeTargetError);
  });

  it("rejects hostnames that resolve to private IPv6", async () => {
    await expect(
      validateAndResolveScrapeURL("https://folio.example/article", {
        resolver: async () => [{ address: "fd00::1234", family: 6 }],
        fetchImpl: async () => ({
          status: 200,
          headers: { get: () => null },
        }),
      }),
    ).rejects.toBeInstanceOf(UnsafeScrapeTargetError);
  });

  it("rejects mixed DNS results when any resolved address is private", async () => {
    await expect(
      validateAndResolveScrapeURL("https://folio.example/article", {
        resolver: async () => [
          { address: "93.184.216.34", family: 4 },
          { address: "10.0.0.5", family: 4 },
        ],
        fetchImpl: async () => ({
          status: 200,
          headers: { get: () => null },
        }),
      }),
    ).rejects.toBeInstanceOf(UnsafeScrapeTargetError);
  });

  it("allows public hostnames resolved through 198.18/19 benchmark proxy addresses", async () => {
    const finalURL = await validateAndResolveScrapeURL("https://example.com/article", {
      resolver: async () => [{ address: "198.18.0.20", family: 4 }],
      fetchImpl: async () => ({
        status: 200,
        headers: { get: () => null },
      }),
    });

    expect(finalURL).toBe("https://example.com/article");
  });

  it("rejects redirect chains that jump into private networks", async () => {
    const fetchCalls: string[] = [];

    await expect(
      validateAndResolveScrapeURL("https://public.example/post", {
        resolver: async (hostname) => {
          if (hostname === "public.example") {
            return [{ address: "93.184.216.34", family: 4 }];
          }
          if (hostname === "169.254.169.254") {
            return [{ address: "169.254.169.254", family: 4 }];
          }
          return [{ address: "93.184.216.35", family: 4 }];
        },
        fetchImpl: async (input) => {
          fetchCalls.push(input);
          return {
            status: 302,
            headers: { get: () => "http://169.254.169.254/latest/meta-data" },
          };
        },
      }),
    ).rejects.toBeInstanceOf(UnsafeScrapeTargetError);

    expect(fetchCalls).toEqual(["https://public.example/post"]);
  });

  it("returns the final public URL after safe redirects", async () => {
    const fetchCalls: string[] = [];

    const finalURL = await validateAndResolveScrapeURL("https://public.example/post", {
      resolver: async (hostname) => {
        if (hostname === "public.example") {
          return [{ address: "93.184.216.34", family: 4 }];
        }
        if (hostname === "www.public.example") {
          return [{ address: "93.184.216.35", family: 4 }];
        }
        return [{ address: "93.184.216.36", family: 4 }];
      },
      fetchImpl: async (input) => {
        fetchCalls.push(input);
        if (input === "https://public.example/post") {
          return {
            status: 301,
            headers: { get: () => "/canonical" },
          };
        }
        return {
          status: 200,
          headers: { get: () => null },
        };
      },
    });

    expect(finalURL).toBe("https://public.example/canonical");
    expect(fetchCalls).toEqual([
      "https://public.example/post",
      "https://public.example/canonical",
    ]);
  });

  it("falls back to the original public URL when redirect probing fails", async () => {
    const finalURL = await validateAndResolveScrapeURL("https://public.example/post", {
      resolver: async () => [{ address: "93.184.216.34", family: 4 }],
      fetchImpl: async () => {
        throw new Error("network probe failed");
      },
    });

    expect(finalURL).toBe("https://public.example/post");
  });
});
