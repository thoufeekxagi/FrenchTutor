import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { LearnerProvider } from "../components/learner-provider";
import { SiteAnalytics } from "./site-analytics";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://parlesprint.com";
const title = "ParleSprint | Free French practice for your everyday";
const description = "Free daily French practice, useful writing tools, verb exercises and your own vocabulary notebook. Start without an account. Build confidence for everyday life in Canada.";

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

export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#f5f6f8", colorScheme: "light" };

const structuredData = [
  {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "ParleSprint",
    url: siteUrl,
    logo: `${siteUrl}/icon-512.png`,
    description,
  },
  {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "ParleSprint",
    applicationCategory: "EducationalApplication",
    operatingSystem: "iOS, Web, Chrome",
    url: siteUrl,
    description,
    featureList: [
      "Free daily French practice",
      "Live French speaking practice",
      "Personal vocabulary notebook",
      "Essential verb practice",
      "French reading and listening practice",
      "Writing practice with feedback",
      "TEF and TCF Canada-oriented preparation",
    ],
  },

];

const gaId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-CA" className={inter.variable}>
      <body className="font-sans antialiased">
        <LearnerProvider>{children}
        {gaId && <SiteAnalytics gaId={gaId} />}
        </LearnerProvider>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
      </body>
    </html>
  );
}
