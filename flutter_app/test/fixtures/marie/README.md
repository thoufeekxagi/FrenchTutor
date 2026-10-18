`learner_fr_16k.pcm` is a synthetic French voice fixture (16 kHz mono PCM16).
It was generated on macOS with:

```sh
say -v Amélie -o /tmp/parlesprint-learner-voice.aiff \
  'Bonjour Marie. Parlez plus lentement, s’il vous plaît.'
ffmpeg -i /tmp/parlesprint-learner-voice.aiff -f s16le -ac 1 -ar 16000 \
  learner_fr_16k.pcm
```

It contains no learner recording or personal data. Its purpose is to replay
speech-shaped PCM through the production input gate without a phone or network.
