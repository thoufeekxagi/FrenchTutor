import type { Metadata } from "next";
import { ConfirmSignupClient } from "./confirm-signup-client";

export const metadata: Metadata = {
  title: "Confirm your ParleSprint account",
  robots: { index: false, follow: false, nocache: true },
};

export default function ConfirmSignupPage() {
  return <ConfirmSignupClient />;
}
