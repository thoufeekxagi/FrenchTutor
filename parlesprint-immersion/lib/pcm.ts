export const TRANSCRIPTION_SAMPLE_RATE = 16000;

export function resamplePcm16(input: Float32Array, inputRate: number): Int16Array {
  if (inputRate <= 0 || !input.length) return new Int16Array();
  const ratio = inputRate / TRANSCRIPTION_SAMPLE_RATE;
  const length = Math.max(1, Math.floor(input.length / ratio));
  const output = new Int16Array(length);
  for (let i = 0; i < length; i++) {
    const position = i * ratio;
    const left = Math.min(input.length - 1, Math.floor(position));
    const right = Math.min(input.length - 1, left + 1);
    const fraction = position - left;
    const sample = input[left]! * (1 - fraction) + input[right]! * fraction;
    const clipped = Math.max(-1, Math.min(1, sample));
    output[i] = clipped < 0 ? clipped * 32768 : clipped * 32767;
  }
  return output;
}

/** Root-mean-square level of a mono float block (0 to 1). */
export function rms(samples: Float32Array): number {
  if (!samples.length) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) sum += samples[i]! * samples[i]!;
  return Math.sqrt(sum / samples.length);
}

export interface GateStep {
  send: boolean;
  /** Speech just started again: send the held-back lead-in chunk first. */
  resumed: boolean;
  /** Silence has lasted long enough: tell the provider the stream paused. */
  flush: boolean;
}

/** Skips silent audio (billed by the minute) while keeping word onsets and sentence ends intact. */
export class SilenceGate {
  private lastLoud = -Infinity;
  private speaking = false;
  private flushed = true;
  constructor(
    private readonly threshold = 0.004,
    private readonly hangoverMs = 700,
    private readonly flushAfterMs = 1200,
  ) {}
  push(level: number, nowMs: number): GateStep {
    if (level >= this.threshold) {
      const resumed = !this.speaking;
      this.lastLoud = nowMs;
      this.speaking = true;
      this.flushed = false;
      return { send: true, resumed, flush: false };
    }
    if (nowMs - this.lastLoud <= this.hangoverMs) return { send: true, resumed: false, flush: false };
    this.speaking = false;
    if (!this.flushed && nowMs - this.lastLoud >= this.flushAfterMs) {
      this.flushed = true;
      return { send: false, resumed: false, flush: true };
    }
    return { send: false, resumed: false, flush: false };
  }
}
