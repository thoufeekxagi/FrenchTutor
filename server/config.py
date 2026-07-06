import os
from dotenv import load_dotenv

load_dotenv()

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_BASE_URL = "https://api.groq.com/openai/v1"

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))

STT_MODEL = os.getenv("STT_MODEL", "whisper-large-v3-turbo")
LLM_PRIMARY = os.getenv("LLM_PRIMARY", "llama-3.3-70b-versatile")
LLM_FALLBACK = os.getenv("LLM_FALLBACK", "llama-3.1-8b-instant")

TTS_VOICE = os.getenv("TTS_VOICE", "fr-FR-DeniseNeural")
TTS_RATE = os.getenv("TTS_RATE", "+0%")

MAX_HISTORY_MESSAGES = int(os.getenv("MAX_HISTORY_MESSAGES", "20"))

DB_PATH = os.path.join(os.path.dirname(__file__), "french_tutor.db")

KEY_G = os.getenv("GROQ_API_KEY", "")
