/** Product settings in one place. Edit here; no UI code needs to change. */
export const APP = {
  name: "ParleSprint Immersion",
  feedbackEmail: "thoufeekbaber1@gmail.com",
  /** Stripe payment link for supporters. The Support row stays hidden while this is empty. */
  supportUrl: "",
  /** Switch to "pro" when a paid tier exists; see lib/plan.ts. */
  plan: "free" as "free" | "pro",
};

export function feedbackUrl(version: string): string {
  const subject = encodeURIComponent(`${APP.name} feedback`);
  const body = encodeURIComponent(`\n\n---\nVersion ${version}\nWhat I was watching:\nWhat I expected:\nWhat happened:`);
  return `mailto:${APP.feedbackEmail}?subject=${subject}&body=${body}`;
}
