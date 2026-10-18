/** One-time asset generation; no secret or provider SDK is shipped to the browser. */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
const root = path.resolve(import.meta.dirname, "..");
const envPath = process.env.PRACTICE_ENV_FILE;
if (!envPath)
  throw Error("Set PRACTICE_ENV_FILE to a local server environment file.");
const key = fs
  .readFileSync(envPath, "utf8")
  .match(/^GEMINI_API_KEY\s*=\s*["']?([^\r\n"']+)/m)?.[1];
if (!key) throw Error("GEMINI_API_KEY missing.");
const model = "gemini-3.8-flash-lite-tts";
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "parlesprint-practice-"));
const text = fs
  .readFileSync(path.join(root, "public/demo-fr.srt"), "utf8")
  .trim()
  .split(/\n\s*\n/)
  .map((block) => block.split("\n").slice(2).join(" "));
const teaching = [
  {
    translation: "Hello! Today, I am preparing for my first trip to Quebec.",
    grammar:
      "Aujourd'hui means today. Je prépare uses the present tense of préparer.",
  },
  {
    translation: "I would like to book a room for two nights, please.",
    grammar:
      "Je voudrais is a polite way to say I would like. Pour deux nuits gives the duration.",
  },
  {
    translation: "Is breakfast included in the price?",
    grammar:
      "Est-ce que turns a statement into a question. Compris means included here.",
  },
  {
    translation: "Yesterday, I forgot my ticket on the train.",
    grammar: "J'ai oublié is the passé composé: avoir plus a past participle.",
  },
  {
    translation: "Fortunately, someone found it and gave it back to me.",
    grammar: "L' stands for le billet. Me means to me in me l'a rendu.",
  },
  {
    translation: "Even if I make mistakes, I keep speaking French.",
    grammar: "Même si means even if. Continuer à is followed by an infinitive.",
  },
  {
    translation: "By practising a little every day, I am gaining confidence.",
    grammar:
      "À force de plus an infinitive expresses a result from repeated effort.",
  },
];
const cues = [];
const clips = [];
let time = 0;
for (const [i, sentence] of text.entries()) {
  const response = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/interactions",
    {
      method: "POST",
      headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        input: [
          {
            type: "user_input",
            content: [
              {
                type: "text",
                text: sentence,
                annotations: [
                  {
                    type: "speech_metadata",
                    style:
                      "French, clear and warm, a little slowly for an adult beginner learning French. Read exactly the transcript.",
                  },
                ],
              },
            ],
          },
        ],
        response_format: { type: "audio" },
        generation_config: { speech_config: [{ voice: "Kore" }] },
      }),
      signal: AbortSignal.timeout(90000),
    },
  );
  const data = await response.json();
  if (!response.ok)
    throw Error(
      `TTS failed (${response.status}): ${data.error?.status ?? "unknown"}`,
    );
  const audio = (data.steps ?? [])
    .flatMap((step) => step.content ?? [])
    .filter((part) => part.type === "audio")
    .at(-1);
  if (!audio?.data) throw Error("TTS returned no audio.");
  const raw = path.join(temp, `${i}.wav`);
  fs.writeFileSync(raw, Buffer.from(audio.data, "base64"));
  const duration = Number(
    execFileSync(
      "ffprobe",
      [
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        raw,
      ],
      { encoding: "utf8" },
    ).trim(),
  );
  if (!Number.isFinite(duration) || duration < 0.5 || duration > 20)
    throw Error("Unexpected speech duration.");
  const clip = path.join(temp, `${i}-padded.wav`);
  execFileSync("ffmpeg", [
    "-hide_banner",
    "-loglevel",
    "error",
    "-i",
    raw,
    "-af",
    "apad=pad_dur=0.4",
    "-ar",
    "24000",
    "-ac",
    "1",
    "-c:a",
    "pcm_s16le",
    clip,
  ]);
  clips.push(clip);
  cues.push({
    id: `practice-${i + 1}`,
    start: Number(time.toFixed(3)),
    end: Number((time + duration).toFixed(3)),
    text: sentence,
    ...teaching[i],
  });
  time += duration + 0.4;
  console.log(`Phrase ${i + 1}/${text.length}: ${duration.toFixed(2)} seconds`);
}
const list = path.join(temp, "concat.txt");
fs.writeFileSync(list, clips.map((file) => `file '${file}'`).join("\n"));
const audioFile = path.join(temp, "practice.wav");
execFileSync("ffmpeg", [
  "-hide_banner",
  "-loglevel",
  "error",
  "-f",
  "concat",
  "-safe",
  "0",
  "-i",
  list,
  "-c:a",
  "pcm_s16le",
  audioFile,
]);
// Original understated visual: abstract teal/light circles; no third-party footage.
execFileSync("ffmpeg", [
  "-hide_banner",
  "-loglevel",
  "error",
  "-f",
  "lavfi",
  "-i",
  "color=c=0x0e403b:s=960x540:r=12",
  "-i",
  audioFile,
  "-vf",
  "drawbox=x=80:y=90:w=800:h=360:color=0x174e47:t=fill,drawbox=x=110:y=120:w=8:h=300:color=0xc5e4aa:t=fill",
  "-c:v",
  "libvpx-vp9",
  "-b:v",
  "100k",
  "-c:a",
  "libopus",
  "-b:a",
  "64k",
  "-t",
  String(time),
  "-shortest",
  "-y",
  path.join(root, "public/practice.webm"),
]);
fs.writeFileSync(
  path.join(root, "public/practice.json"),
  JSON.stringify(
    {
      title: "Un voyage au Québec",
      language: "fr",
      duration: Number(time.toFixed(3)),
      disclosure:
        "Original French practice text. Voice synthesized with Google Gemini; not a human speaker.",
      source: {
        provider: "Google Gemini",
        model,
        voice: "Kore",
        documentation:
          "https://ai.google.dev/gemini-api/docs/speech-generation",
        visual: "Original geometric artwork generated locally with FFmpeg",
      },
      cues,
    },
    null,
    2,
  ) + "\n",
);
function srtTime(seconds) {
  const total = Math.round(seconds * 1000);
  const milliseconds = total % 1000;
  const wholeSeconds = Math.floor(total / 1000);
  return `${String(Math.floor(wholeSeconds / 3600)).padStart(2, "0")}:${String(Math.floor(wholeSeconds / 60) % 60).padStart(2, "0")}:${String(wholeSeconds % 60).padStart(2, "0")},${String(milliseconds).padStart(3, "0")}`;
}
fs.writeFileSync(
  path.join(root, "public/practice-fr.srt"),
  cues
    .map(
      (cue, index) =>
        `${index + 1}\n${srtTime(cue.start)} --> ${srtTime(cue.end)}\n${cue.text}`,
    )
    .join("\n\n") + "\n",
);
console.log("Practice assets generated. Temporary source clips:", temp);
