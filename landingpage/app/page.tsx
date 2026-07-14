import { ExamSection, FaqSection, FounderSection, FoundingSection, SiteFooter } from "./conversion-sections";
import { HeroSection, LearnerIdentity, MethodSection, PurposeStrip } from "./hero-and-method";
import { MarieSection, PathwaySection, PersonalizationSection, PracticeModes } from "./platform-sections";
import { MotionController } from "./motion-controller";
import { SiteHeader } from "./site-header";

export default function Home() {
  return (
    <MotionController>
      <main>
      <SiteHeader />
      <HeroSection />
      <PurposeStrip />
      <LearnerIdentity />
      <MethodSection />
      <PracticeModes />
      <PathwaySection />
      <MarieSection />
      <PersonalizationSection />
      <ExamSection />
      <FounderSection />
      <FoundingSection />
      <FaqSection />
      <SiteFooter />
      </main>
    </MotionController>
  );
}
