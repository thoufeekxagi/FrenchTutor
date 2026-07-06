import json
import uuid
import logging
import base64
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from config import HOST, PORT
from memory import init_db, create_session, save_message, get_history, end_session, get_last_session_summary, get_session_transcript, get_all_sessions
from stt import transcribe
from tts import synthesize
from llm import chat, generate_summary

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    logger.info("Server starting up...")
    yield
    logger.info("Server shutting down...")


app = FastAPI(title="French Tutor API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/sessions")
async def list_sessions():
    """Get all past sessions."""
    sessions = get_all_sessions()
    return {"sessions": sessions}


@app.get("/sessions/{session_id}/transcript")
async def get_transcript(session_id: str):
    """Get full transcript for a session."""
    from memory import get_history
    messages = get_history(session_id, limit=10000)
    return {"messages": messages}


@app.websocket("/ws/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    """Main WebSocket endpoint for real-time French tutoring.

    Protocol:
      Client -> Server:
        {"type": "start"} — start session
        {"type": "audio", "data": "<base64 audio>"} — audio chunk
        {"type": "end"} — end session

      Server -> Client:
        {"type": "status", "status": "listening|thinking|speaking"}
        {"type": "transcript", "role": "user|tutor", "text": "..."}
        {"type": "audio", "data": "<base64 mp3>"} — tutor voice reply
        {"type": "session_ended", "summary": "..."}
        {"type": "error", "message": "..."}
    """
    await websocket.accept()
    logger.info(f"WebSocket connected: session={session_id}")

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)
            msg_type = msg.get("type")

            if msg_type == "start":
                create_session(session_id)
                await websocket.send_json({"type": "status", "status": "listening"})
                logger.info(f"Session started: {session_id}")

            elif msg_type == "audio":
                await _handle_audio(websocket, session_id, msg.get("data", ""))

            elif msg_type == "end":
                await _handle_end(websocket, session_id)
                break

    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {session_id}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}", exc_info=True)
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass


async def _handle_audio(websocket: WebSocket, session_id: str, audio_b64: str):
    """Process incoming audio: STT -> LLM -> TTS -> send back."""
    await websocket.send_json({"type": "status", "status": "thinking"})

    try:
        audio_bytes = base64.b64decode(audio_b64)

        user_text = await transcribe(audio_bytes)
        if not user_text.strip():
            await websocket.send_json({"type": "status", "status": "listening"})
            return

        await websocket.send_json({
            "type": "transcript",
            "role": "user",
            "text": user_text,
        })
        save_message(session_id, "user", user_text)

        history = get_history(session_id)
        context = get_last_session_summary()
        reply_text = await chat(history, user_text, context)

        await websocket.send_json({
            "type": "transcript",
            "role": "tutor",
            "text": reply_text,
        })
        save_message(session_id, "assistant", reply_text)

        await websocket.send_json({"type": "status", "status": "speaking"})
        audio_reply = await synthesize(reply_text)
        audio_reply_b64 = base64.b64encode(audio_reply).decode("utf-8")

        await websocket.send_json({
            "type": "audio",
            "data": audio_reply_b64,
        })

        await websocket.send_json({"type": "status", "status": "listening"})

    except Exception as e:
        logger.error(f"Audio processing error: {e}", exc_info=True)
        await websocket.send_json({"type": "error", "message": str(e)})
        await websocket.send_json({"type": "status", "status": "listening"})


async def _handle_end(websocket: WebSocket, session_id: str):
    """End session: generate summary and save."""
    await websocket.send_json({"type": "status", "status": "thinking"})

    transcript = get_session_transcript(session_id)
    summary = await generate_summary(transcript)
    end_session(session_id, summary)

    await websocket.send_json({
        "type": "session_ended",
        "summary": summary,
    })
    logger.info(f"Session ended: {session_id}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host=HOST, port=PORT, reload=True)
