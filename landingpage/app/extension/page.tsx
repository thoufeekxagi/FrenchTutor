import type {Metadata} from "next";
import {SiteFooter} from "../SiteFooter";
import {SiteNav} from "../SiteNav";
import {PageIntro} from "../../components/site-ui";
import {ExtensionDetails} from "./extension-details";

export const metadata: Metadata = {
  title: "French Video Practice for Chrome | ParleSprint Immersion",
  description:
    "Practise French with optional live captions for video, word translations, sentence replay and vocabulary review in Chrome.",
  alternates: {canonical: "/extension"},
};

export default function ExtensionPage() {
  return (
    <>
      <SiteNav />
      <main id="main-content" className="page-shell site-container">
        <PageIntro
          eyebrow="FRENCH VIDEO PRACTICE FOR CHROME"
          title="Turn French video into listening practice."
          description="Start live captions when you want them, understand a phrase, replay the sentence, and save words for later."
        />
        <ExtensionDetails />
      </main>
      <SiteFooter />
    </>
  );
}
