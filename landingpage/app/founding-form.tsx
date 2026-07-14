"use client";

import { Check, Send } from "lucide-react";
import { FormEvent, useState } from "react";

type FormStatus = "idle" | "loading" | "success" | "error";

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
      setMessage(data.message ?? "Your application is in. We’ll be in touch.");
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "We couldn’t submit that. Please try again.");
    }
  }

  if (status === "success") {
    return (
      <div className="application-success" role="status">
        <span><Check size={20} strokeWidth={3} /></span>
        <div><strong>Application received.</strong><p>{message}</p></div>
      </div>
    );
  }

  return (
    <form className="founding-form" onSubmit={submit}>
      <div className="field-grid">
        <label>
          <span>Email address</span>
          <input name="email" type="email" autoComplete="email" placeholder="you@example.com" required />
        </label>
        <label>
          <span>Current French level</span>
          <select name="level" defaultValue="" required>
            <option value="" disabled>Select your level</option>
            <option value="starting">Starting from zero</option>
            <option value="basics">I know some basics</option>
            <option value="conversation">I can hold a simple conversation</option>
            <option value="unsure">I’m not sure</option>
          </select>
        </label>
        <label>
          <span>Main reason for learning</span>
          <select name="goal" defaultValue="" required>
            <option value="" disabled>Select your goal</option>
            <option value="tef-tcf">TEF / TCF Canada</option>
            <option value="work">Work and opportunity</option>
            <option value="life">Everyday life and connection</option>
            <option value="personal">Personal ambition</option>
          </select>
        </label>
        <label>
          <span>Typical practice time</span>
          <select name="pace" defaultValue="" required>
            <option value="" disabled>Select your pace</option>
            <option value="quick">5–10 minutes</option>
            <option value="standard">15–30 minutes</option>
            <option value="deep">30–60 minutes</option>
          </select>
        </label>
      </div>
      <label>
        <span>What has been missing from other French-learning tools? <small>Optional</small></span>
        <textarea name="missing" rows={3} placeholder="Tell us what would make practice genuinely useful for you." />
      </label>
      <button className="button button-light" type="submit" disabled={status === "loading"}>
        {status === "loading" ? "Sending…" : "Apply for founding access"}<Send size={16} />
      </button>
      {status === "error" && <p className="form-error" role="alert">{message}</p>}
      <p className="form-privacy">No payment today. We’ll only use this to contact you about the pilot.</p>
    </form>
  );
}
