#!/usr/bin/env python3
"""Render a local Camille conversation video from the storyboard pilot.

This is deliberately offline and deterministic. macOS `say` creates local
French/English audio, the audio waveform selects complete tutor artwork frames,
and a small Swift helper muxes the rendered frames and audio into an MP4.
It does not call Gemini and it does not touch production session code.
"""

from __future__ import annotations

import math
import subprocess
import sys
import wave
from array import array
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


FPS = 30
WIDTH = 720
HEIGHT = 1280
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


SEGMENTS = [
    {
        "role": "user",
        "voice": "Thomas",
        "text": "Je m'appelle Tofiq.",
    },
    {
        "role": "tutor",
        "voice": "Eddy (French (Canada))",
        "text": "Enchantée, Tofiq ! Moi, c'est Camille. On va pratiquer le français ensemble.",
    },
    {
        "role": "user",
        "voice": "Thomas",
        "text": "Je suis prêt à commencer.",
    },
    {
        "role": "tutor",
        "voice": "Eddy (French (Canada))",
        "text": "Super ! Commençons par une petite conversation.",
    },
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD_PATH if bold else FONT_PATH, size)


def rounded(draw: ImageDraw.ImageDraw, box, fill, radius=24, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def wrap_lines(draw: ImageDraw.ImageDraw, text: str, typeface, max_width: int):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=typeface) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines or [""]


def read_wave_rms(path: Path, count: int) -> list[float]:
    with wave.open(str(path), "rb") as audio:
        sample_rate = audio.getframerate()
        sample_width = audio.getsampwidth()
        channels = audio.getnchannels()
        raw = audio.readframes(audio.getnframes())
    if sample_width != 2:
        raise RuntimeError(f"Expected 16-bit WAV, got {sample_width * 8}-bit")

    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if channels > 1:
        samples = array("h", samples[::channels])

    values = []
    for index in range(count):
        start = int(index / FPS * sample_rate)
        end = int((index + 1) / FPS * sample_rate)
        window = samples[start:end]
        if not window:
            values.append(0.0)
            continue
        values.append(math.sqrt(sum(sample * sample for sample in window) / len(window)) / 32768.0)
    peak = max(values, default=0.0)
    if peak <= 0:
        return values
    return [value / peak for value in values]


def make_audio(root: Path):
    audio_dir = root / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    generated = []
    for index, segment in enumerate(SEGMENTS):
        aiff = audio_dir / f"{index:02d}_{segment['role']}.aiff"
        wav = audio_dir / f"{index:02d}_{segment['role']}.wav"
        subprocess.run(
            ["say", "-v", segment["voice"], "-o", str(aiff), segment["text"]],
            check=True,
        )
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@24000", str(aiff), str(wav)],
            check=True,
        )
        with wave.open(str(wav), "rb") as audio:
            duration = audio.getnframes() / audio.getframerate()
        generated.append({**segment, "wav": wav, "duration": duration})
    return generated


def draw_bubble(draw, text, role, top):
    typeface = font(28, bold=True)
    lines = wrap_lines(draw, text, typeface, 470)
    height = 70 + len(lines) * 34
    left = 46 if role == "tutor" else 204
    right = 674 if role == "tutor" else 674
    fill = "#E3F4F1" if role == "tutor" else "#E7EEFF"
    text_color = "#12233F"
    rounded(draw, (left, top, right, top + height), fill, radius=25)
    label = "Camille" if role == "tutor" else "You"
    draw.text((left + 22, top + 14), label, font=font(18, bold=True), fill="#277F77" if role == "tutor" else "#2B5FC8")
    for line_index, line in enumerate(lines):
        draw.text(
            (left + 22, top + 42 + line_index * 34),
            line,
            font=typeface,
            fill=text_color,
        )
    return top + height


def render_frame(
    avatar_image: Image.Image,
    active_segment: dict,
    history: list[dict],
    status: str,
    output: Path,
    avatar_cache: dict[str, Image.Image],
):
    canvas = Image.new("RGB", (WIDTH, HEIGHT), "#F6F8FB")
    draw = ImageDraw.Draw(canvas)
    draw.text((46, 38), "Conversation", font=font(34, bold=True), fill="#12233F")
    draw.text((46, 80), "Local animation rehearsal · Camille", font=font(18), fill="#63738B")
    draw.line((46, 124, WIDTH - 46, 124), fill="#DEE5EF", width=2)

    bubble_top = 150
    # Keep the rehearsal readable on one portrait screen: the current turn and
    # one previous turn are enough to demonstrate the back-and-forth.
    for message in history[-1:]:
        bubble_top = draw_bubble(draw, message["text"], message["role"], bubble_top) + 12
    bubble_top = draw_bubble(draw, active_segment["text"], active_segment["role"], bubble_top) + 22

    card_left, card_top, card_right, card_bottom = 58, 555, WIDTH - 58, 1055
    rounded(draw, (card_left, card_top, card_right, card_bottom), "#FFFFFF", radius=30, outline="#DDE5EF", width=2)
    avatar = avatar_cache[avatar_image]
    avatar_x = (WIDTH - avatar.width) // 2
    canvas.paste(avatar, (avatar_x, card_top + 30))
    draw.text((46, 1083), "Camille", font=font(28, bold=True), fill="#12233F")
    draw.text((46, 1120), "Warm, clear, and encouraging", font=font(19), fill="#63738B")

    status_fill = "#D9EFEC" if active_segment["role"] == "tutor" else "#E7EEFF"
    status_color = "#277F77" if active_segment["role"] == "tutor" else "#2B5FC8"
    status_width = int(draw.textlength(status, font=font(18, bold=True))) + 62
    rounded(draw, (WIDTH - status_width - 46, 1110, WIDTH - 46, 1158), status_fill, radius=24)
    draw.ellipse((WIDTH - status_width - 27, 1127, WIDTH - status_width - 13, 1141), fill=status_color)
    draw.text((WIDTH - status_width, 1120), status, font=font(18, bold=True), fill="#3C4E6B")
    draw.text((46, 1202), "Audio-driven frame pilot · no production session changes", font=font(15), fill="#8491A4")
    canvas.save(output, quality=95)
    return canvas


def render_frames(root: Path, segments: list[dict]):
    frames_dir = root / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    artwork = Path(__file__).resolve().parents[1] / "assets/images/tutor_camille_storyboard"
    avatar_cache = {
        path.name: Image.open(path).convert("RGB").resize((430, 430), Image.Resampling.LANCZOS)
        for path in artwork.glob("*.png")
    }
    history = []
    timeline = []
    time_cursor = 0.0
    for segment in segments:
        segment = dict(segment)
        segment["start"] = time_cursor
        raw_rms = read_wave_rms(segment["wav"], max(1, math.ceil(segment["duration"] * FPS)))
        # A light envelope follower makes the visual state track speech energy
        # without reacting to every individual audio sample or consonant.
        smoothed_rms = []
        envelope = 0.0
        for value in raw_rms:
            envelope = (0.28 * value) + (0.72 * envelope)
            smoothed_rms.append(envelope)
        segment["rms"] = smoothed_rms
        timeline.append(segment)
        time_cursor += segment["duration"] + 0.32

    total_frames = math.ceil((time_cursor + 0.18) * FPS)
    previous_canvas = None
    previous_key = None
    transition_remaining = 0
    transition_source = None
    active_pose = "listening"
    pose_age = 999
    min_pose_frames = 4

    for frame_index in range(total_frames):
        now = frame_index / FPS
        active_index = max(
            0,
            min(
                len(timeline) - 1,
                next((i for i, item in enumerate(timeline) if now < item["start"] + item["duration"]), len(timeline) - 1),
            ),
        )
        active = timeline[active_index]
        local = now - active["start"]
        rms_index = min(len(active["rms"]) - 1, max(0, int(local * FPS)))
        energy = active["rms"][rms_index] if active["rms"] else 0.0

        if active["role"] == "tutor":
            # Smooth the speech envelope into a small state machine. Hysteresis
            # plus a minimum dwell prevents syllables from causing a jittery
            # open/closed/open sequence.
            if energy > 0.54:
                candidate_pose = "speaking_open.png"
            elif energy > 0.14:
                candidate_pose = "speaking_soft.png"
            else:
                candidate_pose = "listening.png"
            if candidate_pose != active_pose and pose_age >= min_pose_frames:
                active_pose = candidate_pose
                pose_age = 0
            frame_name = active_pose
            pose_age += 1
            status = "Camille is speaking…"
        elif active["role"] == "user":
            frame_name = "listening.png"
            status = "You are speaking…"
            active_pose = frame_name
            pose_age += 1
        else:
            frame_name = "listening.png"
            status = "Listening…"
            active_pose = frame_name
            pose_age += 1

        if frame_name == "listening.png" and int(now * 10) % 47 in (0, 1):
            frame_name = "blink.png"

        prior = [item for item in timeline if item["start"] + item["duration"] <= now]
        current_history = prior[-2:]
        rendered = render_frame(
            frame_name,
            active,
            current_history,
            status,
            frames_dir / f"frame-{frame_index:05d}.png",
            avatar_cache,
        )

        # Mirror the Flutter pilot's AnimatedSwitcher behavior. A short blend
        # is applied whenever the avatar pose or conversation turn changes,
        # preventing hard jumps between AI-generated full-frame illustrations.
        conversation_key = (
            active["role"],
            active["text"],
            tuple(message["text"] for message in current_history[-1:]),
            frame_name,
        )
        if previous_canvas is not None and conversation_key != previous_key:
            transition_source = previous_canvas.copy()
            transition_remaining = 2
        if transition_remaining and transition_source is not None:
            alpha = (3 - transition_remaining) / 3.0
            blended = rendered.copy()
            avatar_box = (145, 585, 575, 1015)
            avatar_transition = Image.blend(
                transition_source.crop(avatar_box),
                rendered.crop(avatar_box),
                alpha,
            )
            blended.paste(avatar_transition, avatar_box[:2])
            blended.save(frames_dir / f"frame-{frame_index:05d}.png", quality=95)
            transition_remaining -= 1
        previous_canvas = rendered
        previous_key = conversation_key

    manifest = root / "audio_manifest.txt"
    with manifest.open("w", encoding="utf-8") as handle:
        for item in timeline:
            handle.write(f"{item['wav']}\t{item['start']:.6f}\n")
    return frames_dir, manifest


def main():
    repo_root = Path(__file__).resolve().parents[2]
    root = repo_root / ".codex-preview/tutor_conversation_demo"
    root.mkdir(parents=True, exist_ok=True)
    generated = make_audio(root)
    frames_dir, manifest = render_frames(root, generated)
    swift_source = Path(__file__).resolve().parent / "render_tutor_conversation.swift"
    binary = root / "render_tutor_conversation"
    subprocess.run(
        [
            "swiftc",
            "-O",
            str(swift_source),
            "-o",
            str(binary),
            "-framework",
            "AVFoundation",
            "-framework",
            "CoreGraphics",
            "-framework",
            "CoreVideo",
            "-framework",
            "ImageIO",
        ],
        check=True,
    )
    output = root / "tutor_conversation_demo.mp4"
    subprocess.run(
        [str(binary), str(frames_dir), str(manifest), str(output)],
        check=True,
    )
    print(output)
    print(f"duration_seconds={sum(item['duration'] + 0.32 for item in generated):.2f}")


if __name__ == "__main__":
    main()
