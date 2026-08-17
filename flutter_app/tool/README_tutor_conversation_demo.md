# Local tutor conversation demo

This rehearsal is intentionally separate from the production Flutter session.
It uses macOS `say` voices to create a deterministic offline conversation, maps
the tutor audio envelope to complete Camille artwork frames, and muxes the
result into an MP4 with native AVFoundation.

Run it from this directory:

```sh
cd /Users/thoufeekx/Desktop/FrenchTutor/flutter_app
python3 -u tool/tutor_conversation_demo.py
```

The output is written to:

`/Users/thoufeekx/Desktop/FrenchTutor/.codex-preview/tutor_conversation_demo/tutor_conversation_demo.mp4`

This is a visual/lip-sync pilot, not a Gemini Live integration. The next step
after approval is to replace the local audio segments with the live tutor
audio stream while keeping the same smoothed pose state machine.
