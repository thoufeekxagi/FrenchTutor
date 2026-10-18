import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { PageIntro } from "../../components/site-ui";
import { AccountWorkspace } from "../../components/account-workspace";
export const metadata:Metadata={title:"Your account & settings | ParleSprint",robots:{index:false,follow:false},alternates:{canonical:"/account"}};
export default function AccountPage(){return <><SiteNav/><main id="main-content" className="page-shell site-container"><PageIntro eyebrow="YOUR SPACE" title="Keep your French close." description="One ParleSprint account. Your words, your preferences, and a useful place to return to."/><AccountWorkspace/></main><SiteFooter/></>;}
