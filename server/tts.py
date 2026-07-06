import edge_tts
import logging
import tempfile
import os
from config import TTS_VOICE, TTS_RATE

logger = logging.getLogger(__name__)


async def synthesize(text: str, voice: str = None, rate: str = None) -> bytes:
    """Convert text to speech using edge-tts.

    Args:
        text: Text to convert to speech.
        voice: Voice name (defaults to config TTS_VOICE).
        rate: Speech rate (defaults to config TTS_RATE).

    Returns:
        Audio bytes in MP3 format.
    """
    voice = voice or TTS_VOICE
    rate = rate or TTS_RATE

    tmp_path = None
    try:
        communicate = edge_tts.Communicate(text, voice, rate=rate)

        tmp_fd, tmp_path = tempfile.mkstemp(suffix=".mp3")
        os.close(tmp_fd)

        await communicate.save(tmp_path)

        with open(tmp_path, "rb") as f:
            audio_bytes = f.read()

        logger.info(f"TTS generated {len(audio_bytes)} bytes for text: {text[:80]}")
        return audio_bytes
    except Exception as e:
        logger.error(f"edge-tts error: {e}")
        raise
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
