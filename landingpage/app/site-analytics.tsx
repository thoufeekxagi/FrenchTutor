"use client";

import { GoogleAnalytics } from "@next/third-parties/google";
import { usePathname } from "next/navigation";

/**
 * Auth handoff links contain a short-lived, one-time Supabase token. Do not
 * load third-party analytics on that route, where the URL could be captured
 * as a page location before the client scrubs it from browser history.
 */
export function SiteAnalytics({ gaId }: { gaId: string }) {
  const pathname = usePathname();
  if (pathname === "/confirm-signup") return null;
  return <GoogleAnalytics gaId={gaId} />;
}
