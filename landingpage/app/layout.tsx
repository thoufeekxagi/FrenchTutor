import type { Metadata, Viewport } from "next";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
const title = "Personalized French Practice with AI Feedback | ParleSprint";
const description = "Learn French through one connected practice loop for vocabulary, grammar, listening, writing, and live AI speaking. Personalized for serious learners, including TEF and TCF Canada goals.";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title,
  description,
  applicationName: "ParleSprint",
  category: "education",
  keywords: [
    "personalized French learning",
    "AI French tutor",
    "French speaking practice",
    "learn French online",
    "French feedback app",
    "French for beginners",
    "TEF Canada preparation",
    "TCF Canada preparation",
    "CLB 7 French",
    "NCLC 7 French",
  ],
  authors: [{ name: "ParleSprint", url: siteUrl }],
  creator: "ParleSprint",
  publisher: "ParleSprint",
  alternates: { canonical: "/" },
  formatDetection: { email: false, address: false, telephone: false },
  openGraph: {
    type: "website",
    locale: "en_CA",
    url: "/",
    siteName: "ParleSprint",
    title,
    description,
  },
  twitter: { card: "summary_large_image", title, description },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 },
  },
  manifest: "/manifest.webmanifest",
};

export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#1b2a4a", colorScheme: "light" };

const structuredData = [
  {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "ParleSprint",
    url: siteUrl,
    logo: `${siteUrl}/parle-mark.svg`,
    description,
  },
  {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "ParleSprint",
    applicationCategory: "EducationalApplication",
    operatingSystem: "iOS and Android",
    url: siteUrl,
    description,
    featureList: [
      "Personalized daily French pathway",
      "Live AI French speaking practice",
      "Spaced-repetition vocabulary",
      "Voice-led grammar practice",
      "French reading and listening practice",
      "Writing practice with feedback",
      "TEF and TCF Canada-oriented preparation",
    ],
  },
];

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-CA">
      <body>
        {children}
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
      </body>
    </html>
  );
}
