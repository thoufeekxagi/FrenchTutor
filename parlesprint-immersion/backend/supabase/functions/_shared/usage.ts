const encoder = new TextEncoder();
const hex = (buffer: ArrayBuffer) =>
  Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, "0")).join("");

export const INSTALLATION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Salted hash so raw IP addresses and installation ids are never stored. */
export async function hmacHex(salt: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(salt), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

/** Client IP as seen by the platform proxy. Prefer the validated Cloudflare header. */
export function clientIp(request: Request): string {
  const cloudflare = request.headers.get("cf-connecting-ip");
  if (cloudflare) return cloudflare.trim();
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    const parts = forwarded.split(",").map((part) => part.trim()).filter(Boolean);
    // Proxies append the real peer last; anything earlier can be supplied by the caller.
    if (parts.length) return parts[parts.length - 1]!;
  }
  return request.headers.get("x-real-ip")?.trim() || "unknown";
}

export interface Limits { install: number; ip: number; global: number; burst: number }
export type UsageResult = "ok" | "install" | "ip" | "global" | "burst" | "invalid" | "unavailable";

const number = (value: string | undefined, fallback: number) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};
export const limitsFromEnv = (prefix: string, defaults: Limits): Limits => ({
  install: number(Deno.env.get(`${prefix}_INSTALL`), defaults.install),
  ip: number(Deno.env.get(`${prefix}_IP`), defaults.ip),
  global: number(Deno.env.get(`${prefix}_GLOBAL`), defaults.global),
  burst: number(Deno.env.get(`${prefix}_BURST`), defaults.burst),
});

/** Atomically counts a request against install, IP, burst and global limits. */
export async function takeUsage(options: {
  url: string;
  serviceKey: string;
  salt: string;
  kind: string;
  installationId: string;
  request: Request;
  units: number;
  limits: Limits;
  signal?: AbortSignal;
}): Promise<UsageResult> {
  if (!options.salt) return "unavailable";
  try {
    const [install, ip] = await Promise.all([
      hmacHex(options.salt, `install:${options.installationId}`),
      hmacHex(options.salt, `ip:${clientIp(options.request)}`),
    ]);
    const response = await fetch(`${options.url}/rest/v1/rpc/immersion_take_usage`, {
      method: "POST",
      headers: { apikey: options.serviceKey, Authorization: `Bearer ${options.serviceKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_kind: options.kind,
        p_install: install,
        p_ip: ip,
        p_units: options.units,
        p_install_limit: options.limits.install,
        p_ip_limit: options.limits.ip,
        p_global_limit: options.limits.global,
        p_burst_limit: options.limits.burst,
      }),
      signal: options.signal ?? AbortSignal.timeout(8000),
    });
    if (!response.ok) return "unavailable";
    const result = await response.json();
    return typeof result === "string" ? (result as UsageResult) : "unavailable";
  } catch {
    return "unavailable";
  }
}
