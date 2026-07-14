import type { Metadata } from "next";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "ParleSprint — Learn French. Move toward NCLC 7.",
    template: "%s | ParleSprint",
  },
  description:
    "A structured French-learning path for English-speaking beginners preparing for TCF or TEF and a Canadian immigration goal.",
  keywords: [
    "learn French for Canadian immigration",
    "TCF Canada preparation",
    "TEF Canada preparation",
    "French for beginners",
    "NCLC 7 French",
  ],
  openGraph: {
    title: "ParleSprint — Learn French. Move toward NCLC 7.",
    description:
      "Start at zero and build toward TCF and TEF readiness with a structured French-learning path.",
    type: "website",
    siteName: "ParleSprint",
  },
  twitter: {
    card: "summary_large_image",
    title: "ParleSprint — Learn French. Move toward NCLC 7.",
    description: "A clearer route from beginner French to TCF and TEF readiness.",
  },
  robots: { index: true, follow: true },
};

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "ParleSprint",
  applicationCategory: "EducationalApplication",
  operatingSystem: "iOS, Android, Web",
  description:
    "A structured French-learning path for English-speaking beginners preparing for TCF or TEF and a Canadian immigration goal.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        {children}
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }} />
      </body>
    </html>
  );
}
