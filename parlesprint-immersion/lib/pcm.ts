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
