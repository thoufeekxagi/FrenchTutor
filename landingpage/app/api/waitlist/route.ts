import { NextResponse } from "next/server";

export const runtime = "nodejs";

type Application = { email?: unknown; level?: unknown; goal?: unknown; pace?: unknown; missing?: unknown };

const allowed = {
  level: new Set(["starting", "basics", "conversation", "unsure"]),
  goal: new Set(["tef-tcf", "work", "life", "personal"]),
  pace: new Set(["quick", "standard", "deep"]),
};

function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Application;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : body.email;
    const missing = typeof body.missing === "string" ? body.missing.trim().slice(0, 1000) : "";

    if (!validEmail(email) || typeof body.level !== "string" || !allowed.level.has(body.level) || typeof body.goal !== "string" || !allowed.goal.has(body.goal) || typeof body.pace !== "string" || !allowed.pace.has(body.pace)) {
      return NextResponse.json({ ok: false, message: "Complete the required fields with valid information." }, { status: 400 });
    }

    const application = { email, level: body.level, goal: body.goal, pace: body.pace, missing, source: "parlesprint-founding-cohort", submittedAt: new Date().toISOString() };
    const webhookUrl = process.env.WAITLIST_WEBHOOK_URL;
    if (!webhookUrl) {
      return NextResponse.json({ ok: false, message: "Application intake is not configured yet. Please check back shortly." }, { status: 503 });
    }

    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(application),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return NextResponse.json({ ok: false, message: "Applications are temporarily unavailable. Please try again shortly." }, { status: 502 });

    return NextResponse.json({ ok: true, message: "You’re on the founding learner list. We’ll contact you when pilot invitations open." });
  } catch {
    return NextResponse.json({ ok: false, message: "Applications are temporarily unavailable. Please try again shortly." }, { status: 500 });
  }
}
