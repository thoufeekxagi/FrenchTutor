import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

type Application = { email?: unknown; level?: unknown; goal?: unknown; pace?: unknown; missing?: unknown; planInterest?: unknown };

const allowed = {
  level: new Set(["starting", "basics", "conversation", "unsure"]),
  goal: new Set(["tef-tcf", "work", "life", "personal"]),
  pace: new Set(["quick", "standard", "deep"]),
  planInterest: new Set(["free", "starter", "year"]),
};

function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Application;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : body.email;
    const missing = typeof body.missing === "string" ? body.missing.trim().slice(0, 1000) : "";
    const planInterest =
      typeof body.planInterest === "string" && allowed.planInterest.has(body.planInterest) ? body.planInterest : null;

    if (!validEmail(email) || typeof body.level !== "string" || !allowed.level.has(body.level) || typeof body.goal !== "string" || !allowed.goal.has(body.goal) || typeof body.pace !== "string" || !allowed.pace.has(body.pace)) {
      return NextResponse.json({ ok: false, message: "Complete the required fields with valid information." }, { status: 400 });
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseKey) {
      return NextResponse.json({ ok: false, message: "Application intake is not configured yet. Please check back shortly." }, { status: 503 });
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    const { error } = await supabase.from("waitlist_applications").insert({
      email,
      level: body.level,
      goal: body.goal,
      pace: body.pace,
      missing,
      plan_interest: planInterest,
    });

    if (error) {
      if (error.code === "23505") {
        return NextResponse.json({ ok: true, message: "You're already on the founding learner list. We'll contact you when pilot invitations open." });
      }
      return NextResponse.json({ ok: false, message: "Applications are temporarily unavailable. Please try again shortly." }, { status: 502 });
    }

    return NextResponse.json({ ok: true, message: "You're on the founding learner list. We'll contact you when pilot invitations open." });
  } catch {
    return NextResponse.json({ ok: false, message: "Applications are temporarily unavailable. Please try again shortly." }, { status: 500 });
  }
}
