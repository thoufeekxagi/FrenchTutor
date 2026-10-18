"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { ArrowRight, LogOut, RefreshCw, ShieldCheck } from "lucide-react";
import { getBrowserClient } from "../lib/auth";
import { useLearner } from "./learner-provider";
import { levels } from "../lib/practice";

type AccountMode = "signin" | "signup" | "reset" | "password";

/* Screen: Account. Primary: use the existing ParleSprint identity or manage the
   signed-in account. The website notebook syncs separately from app progress. */
export function AccountWorkspace() {
  const { user, prefs, setPreferences, sync, syncState, importGuest, signOut, notice } = useLearner();
  const [mode, setMode] = useState<AccountMode>(() =>
    typeof window !== "undefined" && new URLSearchParams(window.location.search).get("mode") === "recovery"
      ? "password"
      : "signin",
  );
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setMessage("");
    setError(false);
    try {
      const client = await getBrowserClient();
      let failure: Error | null = null;
      if (mode === "signin") {
        const result = await client.auth.signInWithPassword({ email: email.trim(), password });
        failure = result.error;
      } else if (mode === "signup") {
        const result = await client.auth.signUp({
          email: email.trim(),
          password,
          options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
        });
        failure = result.error;
        if (!failure) {
          setMessage(result.data.session
            ? "Your account is ready."
            : "Check your inbox to confirm your email. If an account already exists, sign in with its original method or reset its password.");
        }
      } else if (mode === "reset") {
        const result = await client.auth.resetPasswordForEmail(email.trim(), {
          redirectTo: `${window.location.origin}/auth/callback?next=recovery`,
        });
        failure = result.error;
        if (!failure) setMessage("If there’s an account for this email, a reset link is on its way.");
      } else {
        const result = await client.auth.updateUser({ password });
        failure = result.error;
        if (!failure) {
          setMessage("Password updated. You can now sign in with your new password.");
          setPassword("");
          setMode("signin");
        }
      }
      if (failure) throw failure;
    } catch {
      setError(true);
      setMessage(mode === "signin"
        ? "We couldn’t sign you in. Check your email and password, or reset your password."
        : "That request could not be completed. Please try again shortly.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="account-grid">
      <section className="panel">
        {user && mode !== "password" ? (
          <>
            <p className="eyebrow">YOUR PARLESPRINT ACCOUNT</p>
            <h2>A place for your French.</h2>
            <p className="muted">Signed in as <strong>{user.email}</strong></p>
            <p className="notice">
              <ShieldCheck size={17} style={{ display: "inline", marginRight: 7 }} />
              This uses the ParleSprint Supabase account. Your web notebook syncs between signed-in browsers. App lesson progress and app or extension notebooks remain separate until cross-product sync is available.
            </p>
            <p className="subtle-label" role="status">{syncState}</p>
            <div className="notebook-tools" style={{ marginTop: 20 }}>
              <button onClick={() => void sync()} className="button button-secondary"><RefreshCw size={15} />Sync notebook</button>
              <Link href="/words" className="button button-primary">My words <ArrowRight size={15} /></Link>
            </div>
            <button className="text-link" onClick={importGuest}>Add this browser’s guest words to my account</button>
            <div style={{ marginTop: 22, borderTop: "1px solid var(--line)", paddingTop: 14 }}>
              <button className="text-link" onClick={() => void signOut()}><LogOut size={15} />Sign out on this browser</button>
            </div>
            <p className="small-print">For account deletion or help connecting an existing account, <Link href="/support">contact support</Link>. Signing out does not delete your account.</p>
          </>
        ) : (
          <>
            <p className="eyebrow">ONE ACCOUNT. YOUR FRENCH.</p>
            <h2>{mode === "reset" ? "Let’s get you back in." : mode === "password" ? "Choose a new password." : mode === "signup" ? "Make yourself at home." : "Good to have you here."}</h2>
            <p className="muted">
              {mode === "password"
                ? "Use at least 8 characters."
                : "Use the same email and password in the iPhone app, Chrome extension and website to keep one ParleSprint account."}
            </p>

            {mode !== "password" && (
              <div className="auth-tabs">
                <button type="button" className={mode === "signin" ? "active" : ""} onClick={() => { setMode("signin"); setMessage(""); }}>Sign in</button>
                <button type="button" className={mode === "signup" ? "active" : ""} onClick={() => { setMode("signup"); setMessage(""); }}>Create account</button>
              </div>
            )}

            <p className="small-print">Apple sign-in is available in the iPhone app only. Apple-only accounts are not linked to web access yet; contact support before creating another account.</p>

            <form onSubmit={submit}>
              {mode !== "password" && (
                <div className="field">
                  <label htmlFor="email">Email address</label>
                  <input id="email" type="email" autoComplete="email" required maxLength={254} value={email} onChange={(event) => setEmail(event.target.value)} />
                </div>
              )}
              {mode !== "reset" && (
                <div className="field">
                  <label htmlFor="password">{mode === "password" ? "New password" : "Password"}</label>
                  <input id="password" type="password" autoComplete={mode === "signin" ? "current-password" : "new-password"} minLength={mode === "signin" ? 1 : 8} required maxLength={128} value={password} onChange={(event) => setPassword(event.target.value)} />
                </div>
              )}
              <button className="button button-primary" style={{ width: "100%" }} disabled={busy}>
                {busy ? "One moment…" : mode === "signup" ? "Create account" : mode === "reset" ? "Send reset link" : mode === "password" ? "Update password" : "Sign in"}
                <ArrowRight size={16} />
              </button>
            </form>

            {mode === "signin" && <button type="button" className="text-link" onClick={() => { setMode("reset"); setMessage(""); }}>Forgot your password?</button>}
            <p className="small-print">By creating an account, you agree to our <Link href="/terms">Terms</Link> and <Link href="/privacy">Privacy Policy</Link>. Free tools work without an account. No payment details needed.</p>
          </>
        )}
        {(message || notice) && <p role="status" className={`notice ${error ? "error" : ""}`}>{message || notice}</p>}
      </section>

      <section className="panel settings-panel" id="settings">
        <p className="eyebrow">MAKE IT YOURS</p>
        <h2>Learning settings</h2>
        <p className="muted">Saved on this browser. Change them whenever you like.</p>
        <div className="settings-row">
          <div><strong>Practice level</strong><small>Changes the daily challenge and short reading texts.</small></div>
          <select className="input" style={{ width: 80 }} aria-label="Practice level" value={prefs.level} onChange={(event) => setPreferences({ level: event.target.value as typeof prefs.level })}>
            {levels.map((level) => <option key={level}>{level}</option>)}
          </select>
        </div>
        {[
          { key: "largeText" as const, label: "Larger practice text", description: "More room for the words you’re learning." },
          { key: "reducedMotion" as const, label: "Reduce motion", description: "Keep transitions quiet and immediate." },
          { key: "analytics" as const, label: "Share anonymous usage", description: "Optional analytics on public pages. Drafts and saved words are excluded." },
        ].map((setting) => (
          <div className="settings-row" key={setting.key}>
            <div><strong id={`${setting.key}-label`}>{setting.label}</strong><small>{setting.description}</small></div>
            <span className="toggle-target">
              <button className="toggle" role="switch" aria-checked={prefs[setting.key]} aria-labelledby={`${setting.key}-label`} onClick={() => setPreferences({ [setting.key]: !prefs[setting.key] })} />
            </span>
          </div>
        ))}
        <p className="small-print">Your browser’s reduced-motion preference is also respected. Clearing browser data removes guest words, drafts and these settings.</p>
      </section>
    </div>
  );
}
