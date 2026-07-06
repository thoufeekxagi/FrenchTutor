# French Learning Voice Tutor

A free AI-powered French learning app. Speak into your phone, get corrections and voice replies from an AI French tutor.

## Architecture

```
Flutter App (phone) ←→ WebSocket ←→ FastAPI Server (cloud/local)
                                    ├── Groq Whisper API (STT)
                                    ├── Groq Llama 3.3 70B (LLM)
                                    └── edge-tts (TTS)
```

## Prerequisites

1. **Groq API key** — free at https://console.groq.com
2. **Flutter** — install from https://flutter.dev
3. **Python 3.10+**

## Server Setup

```bash
cd server
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env and add your GROQ_API_KEY
python server.py
```

Server runs on `http://0.0.0.0:8000`.

## Flutter App Setup

```bash
cd app
flutter pub get
flutter run
```

For iOS:
```bash
cd ios && pod install && cd ..
flutter run -d ios
```

## Configuration

Update `lib/main.dart` with your server URL:
```dart
const String serverUrl = 'ws://YOUR_SERVER_URL:8000';
```

For local development: `ws://localhost:8000`
For deployed server: `wss://your-render-app.onrender.com`

## Free Tier Limits

| Service | Limit |
|---------|-------|
| Groq LLM (Llama 3.3 70B) | 1,000 req/day, 30 req/min |
| Groq LLM (Llama 3.1 8B fallback) | 14,400 req/day |
| Groq Whisper STT | 2,000 req/day |
| edge-tts | No hard limit |

## Deploy Server (free)

### Render
1. Create new Web Service on https://render.com
2. Connect your repo
3. Build: `pip install -r server/requirements.txt`
4. Start: `cd server && python server.py`
5. Add env var: `GROQ_API_KEY`

### Local + ngrok (for testing)
```bash
# Terminal 1
cd server && python server.py

# Terminal 2
ngrok http 8000
# Use the ngrok URL in your app
```
