import httpx
import logging
from config import GROQ_API_KEY, GROQ_BASE_URL, LLM_PRIMARY, LLM_FALLBACK, MAX_HISTORY_MESSAGES
from prompts import SYSTEM_PROMPT, CONTEXT_PROMPT, SUMMARY_PROMPT

logger = logging.getLogger(__name__)


def _build_messages(history: list[dict], user_text: str, session_context: str = "") -> list[dict]:
    """Build the message list for the LLM API call.

    Args:
        history: List of {role, content} dicts from current session.
        user_text: The user's latest transcribed message.
        session_context: Summary from previous sessions (if any).

    Returns:
        List of messages formatted for OpenAI-compatible API.
    """
    system_content = SYSTEM_PROMPT
    if session_context:
        system_content += "\n\n" + CONTEXT_PROMPT.format(summary=session_context)

    messages = [{"role": "system", "content": system_content}]

    recent = history[-MAX_HISTORY_MESSAGES:]
    for msg in recent:
        messages.append({"role": msg["role"], "content": msg["content"]})

    messages.append({"role": "user", "content": user_text})
    return messages


async def _call_groq(messages: list[dict], model: str) -> str:
    """Make a single call to Groq API.

    Args:
        messages: Message list for the API.
        model: Model name to use.

    Returns:
        Assistant reply text.
    """
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json",
    }

    payload = {
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": 300,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{GROQ_BASE_URL}/chat/completions",
            headers=headers,
            json=payload,
        )
        response.raise_for_status()
        result = response.json()
        reply = result["choices"][0]["message"]["content"].strip()
        logger.info(f"LLM ({model}) reply: {reply[:100]}")
        return reply


async def chat(
    history: list[dict],
    user_text: str,
    session_context: str = "",
) -> str:
    """Get a reply from the French tutor LLM.

    Tries primary model first, falls back to faster model on rate limit errors.

    Args:
        history: Conversation history from current session.
        user_text: User's latest message.
        session_context: Summary from previous sessions.

    Returns:
        Tutor's reply text.
    """
    messages = _build_messages(history, user_text, session_context)

    try:
        return await _call_groq(messages, LLM_PRIMARY)
    except httpx.HTTPStatusError as e:
        status = e.response.status_code
        if status == 429:
            logger.warning(f"Primary model rate limited, falling back to {LLM_FALLBACK}")
            try:
                return await _call_groq(messages, LLM_FALLBACK)
            except Exception as fallback_err:
                logger.error(f"Fallback model also failed: {fallback_err}")
                return "Désolé, I'm having trouble responding right now. Please try again in a moment."
        logger.error(f"LLM error {status}: {e.response.text}")
        return "I'm having trouble right now. Please try again."
    except Exception as e:
        logger.error(f"LLM unexpected error: {e}")
        return "Something went wrong. Please try again."


async def generate_summary(transcript: str) -> str:
    """Generate a session summary from the full transcript.

    Args:
        transcript: Full conversation text from the session.

    Returns:
        Summary text for storage and future context.
    """
    messages = [
        {"role": "system", "content": SUMMARY_PROMPT},
        {"role": "user", "content": f"Here is the session transcript:\n\n{transcript}"},
    ]

    try:
        return await _call_groq(messages, LLM_FALLBACK)
    except Exception as e:
        logger.error(f"Summary generation failed: {e}")
        return "Session completed. Summary unavailable."
