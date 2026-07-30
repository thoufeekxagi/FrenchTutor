import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { GoogleAnalytics } from "@next/third-parties/google";
import "./globals.css";
import { faqs } from "./faq-data";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
const title = "ParleSprint | The French Tutor That Remembers You";
const description = "Speak French every day with Marie, a personal tutor who remembers every mistake and rebuilds tomorrow's lesson around it. Vocabulary, grammar, listening, writing, and real conversation in one daily loop, built toward TEF/TCF Canada readiness.";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title,
  description,
  applicationName: "ParleSprint",
  category: "education",
  keywords: [
    "personalized French learning",
    "online French tutor",
    "French speaking practice",
    "learn French online",
    "French feedback app",
    "French for beginners",
    "TEF Canada preparation",
    "TCF Canada preparation",
    "French learning app iOS Android web",
    "guided French learning path",
  ],
  authors: [{ name: "ParleSprint", url: siteUrl }],
  creator: "ParleSprint",
  publisher: "ParleSprint",
  alternates: { canonical: "/" },
  formatDetection: { email: false, address: false, telephone: false },
  verification: { google: "oURbdVk_I8V02mwzpdcy65qxtzrNqLJWo1J9XK7WI4Q" },
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

export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#007bff", colorScheme: "light" };

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
    operatingSystem: "iOS, Android, and Web",
    url: siteUrl,
    description,
    featureList: [
      "Personalized daily French pathway",
      "Live French speaking practice",
      "Spaced-repetition vocabulary",
      "Voice-led grammar practice",
      "French reading and listening practice",
      "Writing practice with feedback",
      "TEF and TCF Canada-oriented preparation",
    ],
  },
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  },
];

const gaId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-CA" className={inter.variable}>
      <body className="font-sans antialiased">
        {children}
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
      </body>
      {gaId && <GoogleAnalytics gaId={gaId} />}
    </html>
  );
}
