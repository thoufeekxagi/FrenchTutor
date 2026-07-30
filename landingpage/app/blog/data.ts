export type ContentBlock =
  | { type: "p"; text: string }
  | { type: "h2"; text: string }
  | { type: "h3"; text: string }
  | { type: "ul"; items: string[] }
  | { type: "ol"; items: string[] }
  | { type: "quote"; text: string; attribution?: string }
  | { type: "callout"; text: string }
  | { type: "image"; src: string; alt: string; caption?: string }
  | { type: "carousel"; images: { src: string; alt: string; caption?: string }[] }
  | { type: "video"; src: string; caption?: string; poster?: string };

export type BlogPost = {
  slug: string;
  title: string;
  description: string;
  category: string;
  date: string;
  readingTime: string;
  keywords: string[];
  coverImage?: string;
  content: ContentBlock[];
};

export const posts: BlogPost[] = [
  {
    slug: "sle-french-oral-exam-bbb-profile",
    title: "SLE French Oral Exam: A Plain-English Guide to the BBB Profile",
    description:
      "What the Second Language Evaluation actually tests, why the oral component trips up so many federal public servants, and how to practise for it without a generic French course.",
    category: "Professional French",
    date: "2026-07-10",
    readingTime: "7 min read",
    keywords: ["SLE French practice", "BBB profile French test Canada", "second language evaluation French"],
    content: [
      {
        type: "p",
        text: "If you work in or around the federal public service, you've probably heard the letters before anyone explained them: BBB. It's shorthand for a required level on the Second Language Evaluation, or SLE, the test that decides whether your French is strong enough for a bilingual position. Most of what's written about it online is either a government PDF or a course trying to sell you a full curriculum you don't need. This is the plain version.",
      },
      { type: "h2", text: "What the SLE actually measures" },
      {
        type: "p",
        text: "The SLE has three parts: reading comprehension, written expression, and oral proficiency. The oral component is scored on a scale from A to E, and BBB means intermediate-level competence across the three skills, not a top score, just a working, functional level. It's evaluated through a conversation with a live assessor, not a multiple-choice quiz, which is exactly why it feels so different from any French course you took in school.",
      },
      {
        type: "p",
        text: "The oral exam typically runs as a structured but conversational interview. You're asked to describe your job, explain a process, react to a hypothetical workplace situation, and sometimes summarize or paraphrase something you just heard. There's no script to memorize, because the assessor is listening for whether you can actually function in French under normal, unscripted conditions.",
      },
      { type: "h2", text: "Why the oral part is the one that trips people up" },
      {
        type: "p",
        text: "Reading and writing can be studied the way you'd study for any exam: vocabulary lists, grammar drills, practice texts. Speaking can't be crammed the same way, because it depends on retrieval speed, not recognition. Plenty of federal employees can read a French memo without much trouble and still freeze the moment someone asks them a follow-up question out loud. That gap between passive understanding and active production is the entire reason the SLE oral component exists.",
      },
      {
        type: "ul",
        items: [
          "Describing your day-to-day responsibilities in your own words, not a rehearsed script",
          "Reacting naturally when the assessor asks a question you didn't prepare for",
          "Holding a train of thought in French for more than one or two sentences at a time",
          "Recovering smoothly from a mistake instead of stalling out",
        ],
      },
      { type: "h2", text: "What actually helps" },
      {
        type: "p",
        text: "Generic French classes are built for tourists ordering coffee, not for someone who needs to explain a workplace process under mild pressure. What moves the needle for SLE prep specifically is repeated, low-stakes speaking practice that mirrors the format: being asked something you didn't expect, and having to answer out loud, immediately, without a script.",
      },
      {
        type: "callout",
        text: "ParleSprint's live roleplay with Marie is built around exactly this: unscripted conversation, corrected in the moment, calibrated to your actual level rather than a generic curriculum. It's not built or endorsed by the Public Service Commission, but the daily practice of thinking and answering in French, out loud, is the same skill the SLE oral exam is testing.",
      },
      {
        type: "p",
        text: "If you're preparing for a BBB profile, the most useful thing you can do most days isn't another vocabulary list. It's a short, real conversation where you have to respond without knowing the question in advance, then get corrected and try again the next day.",
      },
    ],
  },
  {
    slug: "french-express-entry-crs-points",
    title: "French for Express Entry: What CLB 7 Is Actually Worth, and How to Get There",
    description:
      "How French proficiency affects your Express Entry CRS score, what CLB 7 really requires, and why the speaking section is usually the one holding candidates back.",
    category: "Immigration French",
    date: "2026-07-12",
    readingTime: "8 min read",
    keywords: ["French for Express Entry", "CLB 7 French practice", "CRS points French"],
    content: [
      {
        type: "p",
        text: "Most of what's written about French and Express Entry comes from immigration consultants explaining the points system, not from anyone helping you actually reach the level. This is the other half: what CLB 7 requires in practice, and why the speaking component is usually the last piece to fall into place.",
      },
      { type: "h2", text: "Why French matters for your CRS score" },
      {
        type: "p",
        text: "Express Entry candidates can earn additional Comprehensive Ranking System points for proficiency in French, on top of English, and the bonus becomes meaningful once you reach CLB 7 across all four abilities: listening, speaking, reading, and writing. Below that threshold, French contributes little to your score. At CLB 7 and above, it can meaningfully change your ranking. The exact point values shift with policy updates, so check the current IRCC figures before relying on a specific number, but the shape of the incentive has been consistent: French fluency is one of the few levers a candidate can actually improve through their own effort, rather than waiting on a job offer or a provincial nomination.",
      },
      { type: "h2", text: "What CLB 7 actually means" },
      {
        type: "p",
        text: "The Canadian Language Benchmarks describe CLB 7 as adequate independent function: you can handle everyday and moderately complex situations, participate in a discussion, and manage a conversation you didn't fully anticipate. It's not fluency in the ambitious sense. It's competence under normal, unscripted conditions, which is exactly the skill most courses don't test until the very end, if at all.",
      },
      {
        type: "h3",
        text: "The four sections, and where people actually get stuck",
      },
      {
        type: "ul",
        items: [
          "Reading and listening comprehension: usually the easiest for people who've studied French in school, since they're passive skills",
          "Writing: harder, but still practiced through structured lessons and correction",
          "Speaking: the section most candidates underestimate, because it requires producing language on demand, not recognizing it",
        ],
      },
      {
        type: "p",
        text: "This pattern shows up constantly in immigration forums: a candidate with strong reading and listening scores stalls at CLB 5 or 6 on speaking, not because their grammar is weak, but because they've never had to produce French out loud under time pressure before the actual test does it to them.",
      },
      { type: "h2", text: "Building toward CLB 7 without wasting months on the wrong things" },
      {
        type: "p",
        text: "The most efficient path isn't more grammar. It's structured daily practice that connects vocabulary and grammar directly to speaking, so the words you learn on a Monday are the ones you're asked to actually use in a live conversation, not just recognize on a worksheet.",
      },
      {
        type: "callout",
        text: "ParleSprint's daily pathway threads vocabulary, grammar, listening, and writing into a live roleplay with Marie the same day, specifically so speaking isn't the skill you leave for later. ParleSprint isn't affiliated with IRCC and doesn't guarantee a test score, but daily speaking practice is the single most direct way to close the gap between comprehension and CLB 7 output.",
      },
      {
        type: "p",
        text: "If you're already comfortable reading and listening in French, the honest next step isn't another textbook. It's finding a way to practise producing French out loud, every day, until it stops feeling like translation and starts feeling like speaking.",
      },
    ],
  },
  {
    slug: "read-french-cant-speak-it",
    title: "You Can Read French. You Just Can't Speak It Yet. Here's Why.",
    description:
      "The specific reason years of French class leave people able to read comfortably but unable to hold a conversation, and what closes that gap.",
    category: "Learning French",
    date: "2026-07-14",
    readingTime: "6 min read",
    keywords: ["I can read French but can't speak it", "why can't I speak French"],
    content: [
      {
        type: "p",
        text: "This is one of the most common things adult French learners say, almost word for word: I can read it fine, I understand it when I hear it, but the moment I need to say something myself, nothing comes out. If that's you, the problem isn't a lack of intelligence or a bad ear. It's that reading and speaking are genuinely different skills, and almost nothing in a typical course builds the second one.",
      },
      { type: "h2", text: "Recognition is not production" },
      {
        type: "p",
        text: "When you read a French sentence, your brain is matching patterns it already knows. That's recognition, and it's relatively easy: the answer is right there on the page, and you just have to identify it. Speaking is production. There's no sentence in front of you. You have to build one, from scratch, in real time, while someone is waiting for you to finish. Those are different cognitive tasks, and getting good at one doesn't automatically make you good at the other.",
      },
      {
        type: "p",
        text: "This is why someone can pass a written exam or read a novel in French and still freeze completely when a stranger asks them a simple question at a bakery. The knowledge is there. The retrieval speed for producing it out loud, under mild social pressure, is not, because it was never practised.",
      },
      { type: "h2", text: "Why most courses don't fix this" },
      {
        type: "ul",
        items: [
          "Flashcard apps test recognition: see a word, pick the meaning. That's recognition, not production.",
          "Grammar drills test whether you understand a rule, not whether you can apply it while thinking of what to say next.",
          "Listening exercises test comprehension of someone else's speech, not your own.",
          "Most classroom practice involves reading dialogues aloud, which is pronunciation practice, not spontaneous production.",
        ],
      },
      {
        type: "p",
        text: "None of these are wrong to practise. They're just not the same skill as holding a conversation, and if speaking is the actual goal, they can't be the only thing you do.",
      },
      { type: "h2", text: "What actually closes the gap" },
      {
        type: "p",
        text: "The only way to get faster at producing French out loud is to produce French out loud, repeatedly, in situations where you don't know exactly what's coming next. Rehearsed phrases help for specific situations, but real conversational speed comes from being asked something unexpected and having to answer anyway, then getting corrected, then trying again the next day.",
      },
      {
        type: "quote",
        text: "It feels like being thrown into the ocean and then taught how to swim.",
        attribution: "a common description of French immersion from newcomers to Quebec",
      },
      {
        type: "p",
        text: "That sink-or-swim feeling is what happens when someone jumps straight from recognition-only practice into a real conversation with no bridge in between. The fix isn't avoiding real conversation. It's building the bridge: low-stakes, repeated speaking practice where mistakes are expected and corrected immediately, not judged.",
      },
      {
        type: "callout",
        text: "ParleSprint's live roleplay with Marie exists specifically for this gap: a place to produce French out loud every day, get corrected in the moment, and build the retrieval speed that reading alone never will.",
      },
    ],
  },
  {
    slug: "is-duolingo-enough-for-tef-tcf-canada",
    title: "Is Duolingo Enough for TEF or TCF Canada? What the Speaking Section Actually Requires",
    description:
      "A practical look at what Duolingo and similar apps teach well, what the TEF and TCF speaking sections actually test, and where the gap between the two shows up.",
    category: "TEF & TCF Canada",
    date: "2026-07-16",
    readingTime: "7 min read",
    keywords: ["is Duolingo enough for TEF Canada", "Duolingo TEF Canada", "italki TEF Canada"],
    content: [
      {
        type: "p",
        text: "This question comes up constantly on immigration forums, usually from someone who's put in months on Duolingo and is trying to figure out if that's enough before booking a TEF or TCF Canada exam. The honest answer is: it depends entirely on which section you're asking about, and the section people usually mean when they ask is the one Duolingo helps with least.",
      },
      { type: "h2", text: "What Duolingo actually does well" },
      {
        type: "p",
        text: "Duolingo is genuinely good at building vocabulary recognition and basic grammar pattern familiarity through short, repeated exercises. For the reading and listening comprehension sections of TEF or TCF Canada, that foundation isn't nothing. Plenty of people build real passive vocabulary this way, and it's a reasonable, low-cost starting point for absolute beginners.",
      },
      { type: "h2", text: "Where it stops helping" },
      {
        type: "p",
        text: "The TEF and TCF Canada oral expression sections require you to speak spontaneously, on a topic you're given on the spot, for several minutes, with no script and no multiple choice. Duolingo's speaking exercises, where they exist, generally involve repeating a phrase back or matching an audio clip, which builds pronunciation familiarity but not the ability to construct original sentences under time pressure while an examiner is listening.",
      },
      {
        type: "ul",
        items: [
          "Duolingo: recognize a word, complete a sentence, repeat a phrase back",
          "TEF/TCF oral section: describe a situation, defend an opinion, answer follow-up questions you didn't anticipate",
        ],
      },
      {
        type: "p",
        text: "That's a real gap, not a small one. It's the difference between recognizing French and producing it live, and it's exactly why so many candidates who feel ready based on their app streak are surprised by how hard the oral section feels on exam day.",
      },
      { type: "h2", text: "What about italki and other tutor platforms?" },
      {
        type: "p",
        text: "Human tutors on platforms like italki can absolutely help, and a good tutor who understands the TEF or TCF format is valuable. The tradeoffs are practical ones: booking a session takes planning, sessions are limited by your budget and the tutor's schedule, and consistency, daily or near-daily practice, is hard to sustain at a reasonable cost. For the speaking section specifically, what matters most isn't the quality of any single session, it's the volume of repeated, corrected speaking practice over weeks, which is expensive to get from hourly human tutoring alone.",
      },
      { type: "h2", text: "The realistic combination" },
      {
        type: "p",
        text: "The most honest answer is that vocabulary apps and human tutors both have a role, but neither replaces daily, structured speaking practice that mirrors the actual exam format: unscripted, live, and corrected as you go.",
      },
      {
        type: "callout",
        text: "ParleSprint connects vocabulary, grammar, and listening practice directly into a live roleplay with Marie every day, specifically so the speaking practice isn't left for the week before your exam. It's not affiliated with IRCC, TEF, or TCF, and doesn't guarantee a score, but daily unscripted speaking is the one input the format actually rewards.",
      },
      {
        type: "p",
        text: "If your reading and listening scores already feel solid and the open-ended speaking section is the part you're dreading, that's the honest signal to start practising speaking daily, not to do more flashcards.",
      },
    ],
  },
  {
    slug: "francisation-alternative-quebec-waitlist",
    title: "Can't Get Into a Francisation Class? Here's What to Do While You Wait",
    description:
      "Francisation waitlists in Quebec can run six to twelve months. What that actually means for newcomers, and how to keep making real progress in the meantime.",
    category: "Immigration French",
    date: "2026-07-18",
    readingTime: "6 min read",
    keywords: ["francisation alternative", "francisation Quebec waitlist"],
    content: [
      {
        type: "p",
        text: "If you've tried to register for a francisation class in Quebec recently, you've probably already run into the wait. Reporting on the program has documented waitlists running anywhere from a few months to close to a year, depending on region and course type, and for someone trying to work, integrate, or qualify for a program on a timeline, that wait is the whole problem.",
      },
      { type: "h2", text: "Why the waitlists exist" },
      {
        type: "p",
        text: "Demand for francisation classes has consistently outpaced available seats, and the classes that do run often clash with work schedules, especially for newcomers working full-time or non-standard hours. The result is a familiar, frustrating situation: the free classes you're entitled to exist on paper, but getting an actual seat, at a time that fits your life, is a different story.",
      },
      { type: "h2", text: "What the wait actually costs you" },
      {
        type: "p",
        text: "Every month spent waiting for a class is a month where your French isn't improving through structured practice, at exactly the point in a newcomer's life when day-to-day French matters most: at work, with neighbours, in stores, in interactions where being brushed off in English the moment someone hears an accent is a genuine, documented frustration for francophone-adjacent newcomers.",
      },
      { type: "h2", text: "What actually helps while you wait" },
      {
        type: "ul",
        items: [
          "Daily speaking practice that doesn't depend on a class schedule or a waitlist position",
          "Structured progress you can track yourself, so the wait isn't fully wasted time",
          "Practice that fits around irregular work hours, early mornings or late evenings, not a fixed class slot",
        ],
      },
      {
        type: "p",
        text: "None of this replaces a good in-person francisation class once a seat opens up. Classroom instruction, especially with other learners in the same situation, has real value a solo app can't fully replicate. But there's no reason the months before that seat opens have to be idle.",
      },
      {
        type: "callout",
        text: "ParleSprint's daily pathway and live speaking practice with Marie work around your schedule entirely, no waitlist, no fixed class time, so the months before your francisation seat opens can still move you forward instead of just passing.",
      },
      {
        type: "p",
        text: "If you're on a waitlist right now with no clear date, the honest move isn't to wait for the class to start your French. It's to start now, in whatever pockets of time your schedule actually has, so that by the time your seat opens, you're not starting from zero.",
      },
    ],
  },
];

export function getPostBySlug(slug: string): BlogPost | undefined {
  return posts.find((p) => p.slug === slug);
}

export function getAllSlugs(): string[] {
  return posts.map((p) => p.slug);
}

export function getSortedPosts(): BlogPost[] {
  return [...posts].sort((a, b) => (a.date < b.date ? 1 : -1));
}
