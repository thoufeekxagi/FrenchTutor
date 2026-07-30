import type { ContentBlock } from "../blog/data";

export type StoryUpdate = {
  date: string;
  title: string;
  content: ContentBlock[];
};

export type Story = {
  slug: string;
  name: string;
  role: string;
  tagline: string;
  description: string;
  goal: string;
  startingPoint: string;
  targetLevel: string;
  category: string;
  keywords: string[];
  /** Oldest first. Reverse with getStoryUpdatesSorted for display. */
  updates: StoryUpdate[];
};

export const stories: Story[] = [
  {
    slug: "thoufeek-french-b2-challenge",
    name: "Thoufeek Baber",
    role: "Founder, ParleSprint",
    tagline: "Building the app. Learning the language. Betting on both in public.",
    description:
      "ParleSprint's founder is learning French from scratch using nothing but the app he's building, with one public goal: reach B2 before he lets himself call it done.",
    goal: "Reach French B2, the level generally recognized for independent, everyday fluency, using only ParleSprint. No private tutor, no other app, no shortcuts.",
    startingPoint: "True beginner",
    targetLevel: "B2",
    category: "Founder Journey",
    keywords: [
      "learning French for TEF",
      "learning French for TCF",
      "French learning pathway for PR",
      "French for Express Entry",
      "CLB 7 French",
      "founder learning French",
    ],
    updates: [
      {
        date: "2026-07-19",
        title: "Day one: why I'm learning French in public, with my own app",
        content: [
          {
            type: "p",
            text: "My name is Thoufeek Baber. I'm the founder of ParleSprint, and I'm starting this page to do something a little uncomfortable: learn French, from true zero, in public, using nothing but the product I'm building.",
          },
          {
            type: "p",
            text: "Here's the honest starting point. I don't speak French. Not a little, not \"I took it in school\" French. I'm starting the same place a lot of the people I built this for are starting: reading a menu and guessing, hearing a conversation and catching maybe one word in ten.",
          },
          { type: "h2", text: "The oath" },
          {
            type: "callout",
            text: "I will not call myself done, and I will not call ParleSprint done, until I can sit a real conversation at a B2 level, the level generally recognized for independent, everyday fluency, using only ParleSprint to get there. No private tutor. No other app filling the gaps. If the product can't get its own founder to B2, it doesn't deserve to promise that to anyone else.",
          },
          {
            type: "p",
            text: "That's the whole idea. Putting my own money, and my own time, where the product's mouth is.",
          },
          { type: "h2", text: "Why this, and why now" },
          {
            type: "p",
            text: "A lot of the people ParleSprint is built for are learning French for a reason with a deadline attached to it: the TEF or TCF exam, a French-language pathway toward permanent residence, CLB 7 for Express Entry, a job that needs workplace French. I'm not personally chasing an immigration deadline, but I wanted my own practice to run through the exact same pathway those learners will use, the same daily loop of vocabulary, grammar, listening, and writing that feeds into a live roleplay with Marie, so that every gap I hit is a gap a real learner would hit too.",
          },
          {
            type: "p",
            text: "If the daily loop is going to work for someone studying toward TEF Canada or TCF Canada, it has to work on me first, with no special treatment and no admin shortcuts.",
          },
          { type: "h2", text: "What I'm committing to" },
          {
            type: "ul",
            items: [
              "A real update here, roughly monthly, sometimes sooner if something breaks or something clicks",
              "Honest reporting, including the weeks where progress stalls, not just the good ones",
              "No fluency-in-three-months claims about myself either. B2 takes real hours. I'll say how many, and how it's going, not a fake timeline.",
            ],
          },
          {
            type: "p",
            text: "If you're learning French for the same reasons a lot of ParleSprint's early learners are, TEF, TCF, Express Entry, CLB 7, or just to finally speak instead of only reading, follow along. We're starting from the same place, today.",
          },
        ],
      },
    ],
  },
];

export function getStoryBySlug(slug: string): Story | undefined {
  return stories.find((s) => s.slug === slug);
}

export function getAllStorySlugs(): string[] {
  return stories.map((s) => s.slug);
}

export function getStoryUpdatesSorted(story: Story): StoryUpdate[] {
  return [...story.updates].sort((a, b) => (a.date < b.date ? 1 : -1));
}

export function getLatestUpdate(story: Story): StoryUpdate | undefined {
  return getStoryUpdatesSorted(story)[0];
}
