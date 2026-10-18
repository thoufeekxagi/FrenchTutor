import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { PageIntro } from "../../components/site-ui";
import { FeedbackForm } from "./feedback-form";
export const metadata:Metadata={title:"Help shape ParleSprint | Share feedback",description:"Tell the ParleSprint team what helps your French and what you need next. Your message goes straight to the team.",robots:{index:false,follow:false},alternates:{canonical:"/feedback"}};
export default function FeedbackPage(){return <><SiteNav/><main id="main-content" className="page-shell narrow-container"><PageIntro eyebrow="WE’RE LISTENING" title="Your everyday French matters." description="What’s hard to find? What’s not working? Tell us what would make learning a little easier. This note goes straight to the ParleSprint team."/><FeedbackForm/></main><SiteFooter/></>;}
