import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { PageIntro } from "../../components/site-ui";
import { DailyPractice } from "../../components/daily-practice";
export const metadata:Metadata={title:"Free daily French practice | ParleSprint",description:"A short French practice for A1, A2, B1 and B2. Read, answer and save a useful phrase. Free, with no signup required.",alternates:{canonical:"/today"}};
export default function TodayPage(){return <><SiteNav/><main id="main-content" className="page-shell narrow-container"><PageIntro eyebrow="YOUR DAILY PRACTICE" title="A few minutes. A little more confidence." description="Choose your level, read a little French, and take one useful phrase into your day."/><DailyPractice/></main><SiteFooter/></>;}
