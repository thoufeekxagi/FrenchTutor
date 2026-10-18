import type { Metadata } from "next";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { PageIntro } from "../../components/site-ui";
import { NotebookWorkspace } from "../../components/notebook-workspace";
export const metadata:Metadata={title:"Your French vocabulary notebook | ParleSprint",robots:{index:false,follow:false},alternates:{canonical:"/words"}};
export default function WordsPage(){return <><SiteNav/><main id="main-content" className="page-shell site-container"><PageIntro eyebrow="YOUR PERSONAL NOTEBOOK" title="The words worth keeping." description="Useful phrases, little discoveries, words you want to use again. Keep them together."/><NotebookWorkspace/></main><SiteFooter/></>;}
