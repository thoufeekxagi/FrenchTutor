import httpx
import logging
from config import GROQ_API_KEY, GROQ_BASE_URL, STT_MODEL

logger = logging.getLogger(__name__)


async def transcribe(audio_bytes: bytes, language: str = "fr") -> str:
    """Transcribe audio bytes to text using Groq Whisper API.

    Args:
        audio_bytes: Raw audio data (webm/ogg/wav format).
        language: Language hint for transcription (fr, en, or None for auto).

    Returns:
        Transcribed text string.
    """
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
    }

    files = {
        "file": ("audio.webm", audio_bytes, "audio/webm"),
    }

    data = {
        "model": STT_MODEL,
        "response_format": "json",
    }
    if language:
        data["language"] = language

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{GROQ_BASE_URL}/audio/transcriptions",
                headers=headers,
                files=files,
                data=data,
            )
            response.raise_for_status()
            result = response.json()
            text = result.get("text", "").strip()
            logger.info(f"STT result: {text[:100]}")
            return text
    except httpx.HTTPStatusError as e:
        logger.error(f"Groq Whisper HTTP error: {e.response.status_code} - {e.response.text}")
        raise
    except Exception as e:
        logger.error(f"Groq Whisper error: {e}")
        raise
