"use client";

import { Check, Send } from "lucide-react";
import { FormEvent, useState } from "react";
import { sendGAEvent } from "@next/third-parties/google";

type FormStatus = "idle" | "loading" | "success" | "error";

const inputClasses = "w-full rounded-xl border border-[#e5e7eb] bg-white px-4 py-3 text-sm font-medium text-[#1C1E21] outline-none transition-colors focus:border-[#007BFF] focus:ring-2 focus:ring-[#007BFF]/15 placeholder:text-[#9ca3af]";
const labelClasses = "flex flex-col gap-1.5 text-xs font-semibold text-[#33383F]";

export function FoundingForm() {
  const [status, setStatus] = useState<FormStatus>("idle");
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("loading");
    setMessage("");
    const form = new FormData(event.currentTarget);
    const payload = Object.fromEntries(form.entries());

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = (await response.json()) as { ok?: boolean; message?: string };
      if (!response.ok || !data.ok) throw new Error(data.message ?? "Application unavailable.");
      setStatus("success");
      setMessage(data.message ?? "Your application is in. We'll be in touch.");
      sendGAEvent("event", "generate_lead", { form: "founding_waitlist" });
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "We couldn't submit that. Please try again.");
    }
  }

  if (status === "success") {
    return (
      <div className="flex items-start gap-3 rounded-2xl bg-[#e7f6ec] p-5" role="status">
        <span className="mt-0.5 flex h-8 w-8 flex-none items-center justify-center rounded-full bg-[#28A745] text-white">
          <Check size={16} strokeWidth={3} />
        </span>
        <div>
          <strong className="block text-sm font-bold text-[#1C1E21]">Application received.</strong>
          <p className="mt-1 text-sm font-medium text-[#33383F]">{message}</p>
        </div>
      </div>
    );
  }

  return (
    <form className="flex flex-col gap-4" onSubmit={submit}>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className={labelClasses}>
          <span>Email address</span>
          <input className={inputClasses} name="email" type="email" autoComplete="email" placeholder="you@example.com" required />
        </label>
        <label className={labelClasses}>
          <span>Current French level</span>
          <select className={inputClasses} name="level" defaultValue="" required>
            <option value="" disabled>Select your level</option>
            <option value="starting">Starting from zero</option>
            <option value="basics">I know some basics</option>
            <option value="conversation">I can hold a simple conversation</option>
            <option value="unsure">I&apos;m not sure</option>
          </select>
        </label>
        <label className={labelClasses}>
          <span>Main reason for learning</span>
          <select className={inputClasses} name="goal" defaultValue="" required>
            <option value="" disabled>Select your goal</option>
            <option value="tef-tcf">TEF / TCF Canada</option>
            <option value="work">Work and opportunity</option>
            <option value="life">Everyday life and connection</option>
            <option value="personal">Personal ambition</option>
          </select>
        </label>
        <label className={labelClasses}>
          <span>Typical practice time</span>
          <select className={inputClasses} name="pace" defaultValue="" required>
            <option value="" disabled>Select your pace</option>
            <option value="quick">5 to 10 minutes</option>
            <option value="standard">15 to 30 minutes</option>
            <option value="deep">30 to 60 minutes</option>
          </select>
        </label>
      </div>
      <label className={labelClasses}>
        <span>Which plan interests you? <small className="font-normal text-[#9ca3af]">Optional</small></span>
        <select className={inputClasses} name="planInterest" defaultValue="">
          <option value="">Not sure yet</option>
          <option value="free">Free — 60 min/day, forever</option>
          <option value="starter">Founding Starter — $9.99, 3 months</option>
          <option value="year">Founding Year — $49.99, 12 months</option>
        </select>
      </label>
      <label className={labelClasses}>
        <span>What has been missing from other French-learning tools? <small className="font-normal text-[#9ca3af]">Optional</small></span>
        <textarea className={inputClasses} name="missing" rows={3} placeholder="Tell us what would make practice genuinely useful for you." />
      </label>
      <button
        className="mt-1 flex min-h-[48px] w-full items-center justify-center gap-2 rounded-xl bg-[#1C1E21] text-sm font-bold text-white transition-all hover:bg-[#33383F] disabled:cursor-wait disabled:opacity-60"
        type="submit"
        disabled={status === "loading"}
      >
        {status === "loading" ? "Sending..." : "Apply for founding access"}<Send size={15} />
      </button>
      {status === "error" && <p className="text-sm font-semibold text-[#dc2626]" role="alert">{message}</p>}
      <p className="text-xs font-medium text-[#9ca3af]">No payment today. We&apos;ll only use this to contact you about the pilot.</p>
    </form>
  );
}
