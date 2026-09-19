"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import styles from "./confirm-signup.module.css";
import { getSafeConfirmationUrl } from "./confirmation-link";

type ConfirmationState =
  | { status: "preparing" }
  | { status: "ready"; url: string }
  | { status: "invalid" }
  | { status: "opening" };

export function ConfirmSignupClient() {
  const [confirmation, setConfirmation] = useState<ConfirmationState>({
    status: "preparing",
  });

  useEffect(() => {
    const safeUrl = getSafeConfirmationUrl(window.location.href);

    // The Supabase token remains in component memory for the explicit action,
    // but not in browser history or subsequent same-origin referrers.
    window.history.replaceState(window.history.state, "", "/confirm-signup");

    const updateState = window.setTimeout(() => {
      setConfirmation(
        safeUrl ? { status: "ready", url: safeUrl } : { status: "invalid" },
      );
    }, 0);
    return () => window.clearTimeout(updateState);
  }, []);

  function openConfirmation() {
    if (confirmation.status !== "ready") return;
    const url = confirmation.url;
    setConfirmation({ status: "opening" });
    // This only runs after the user presses the button. Merely prefetching or
    // displaying the landing page never consumes Supabase's one-time token.
    window.location.assign(url);
  }

  const isReady = confirmation.status === "ready";

  return (
    <main className={styles.page}>
      <section className={styles.card} aria-labelledby="confirm-title">
        <div className={styles.brand}>
          <Image
            src="/parle-mark.svg"
            alt=""
            width={48}
            height={48}
            priority
          />
          <span>ParleSprint</span>
        </div>

        <div className={styles.copy}>
          <p className={styles.eyebrow}>ONE QUICK STEP</p>
          <h1 id="confirm-title">Confirm your account</h1>
          <p className={styles.description}>
            Confirm this email address to save your French learning path and
            progress. On iPhone, the confirmation will return you to
            ParleSprint.
          </p>
        </div>

        {confirmation.status === "preparing" && (
          <p className={styles.status} role="status">
            Preparing your secure confirmation link…
          </p>
        )}
        {confirmation.status === "invalid" && (
          <div className={styles.notice} role="alert">
            <strong>This link is incomplete or has expired.</strong>
            <span>
              Open ParleSprint and request a fresh confirmation email, then tap
              its link on this iPhone.
            </span>
          </div>
        )}
        {confirmation.status === "opening" && (
          <p className={styles.status} role="status">
            Opening ParleSprint…
          </p>
        )}

        {isReady ? (
          <button
            className={styles.action}
            type="button"
            onClick={openConfirmation}
          >
            Confirm email and open ParleSprint
            <span aria-hidden="true">→</span>
          </button>
        ) : confirmation.status === "invalid" ? (
          <a className={styles.secondaryAction} href="https://parlesprint.com">
            Return to ParleSprint
          </a>
        ) : null}

        <p className={styles.footer}>
          If you didn’t create a ParleSprint account, you can ignore this page.
        </p>
      </section>
    </main>
  );
}
