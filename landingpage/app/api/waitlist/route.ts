import { NextResponse } from "next/server";

export const runtime = "nodejs";

function isValidEmail(value: unknown): value is string {
  return typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { email?: unknown };
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : body.email;
    if (!isValidEmail(email)) {
      return NextResponse.json({ ok: false, message: "Enter a valid email address." }, { status: 400 });
    }

    const webhookUrl = process.env.WAITLIST_WEBHOOK_URL;
    if (webhookUrl) {
      const response = await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, source: "parlesprint-landing-page" }),
      });
      if (!response.ok) {
        return NextResponse.json({ ok: false, message: "The waitlist is temporarily unavailable." }, { status: 502 });
      }
    }

    return NextResponse.json({ ok: true, preview: !webhookUrl });
  } catch {
    return NextResponse.json({ ok: false, message: "The waitlist is temporarily unavailable." }, { status: 500 });
  }
}
