import { describe, expect, it } from "vitest";
import { rms, SilenceGate, resamplePcm16, TRANSCRIPTION_SAMPLE_RATE } from "./pcm";

describe("tab audio conversion for Gemini Live", () => {
  it("produces mono 16 kHz signed PCM from 48 kHz audio", () => {
    const input = new Float32Array(4800).fill(0.5);
    const result = resamplePcm16(input, 48000);
    expect(result).toHaveLength(1600);
    expect(result[0]).toBe(16383);
    expect(result.every((sample) => sample >= -32768 && sample <= 32767)).toBe(true);
    expect(TRANSCRIPTION_SAMPLE_RATE).toBe(16000);
  });

  it("passes through 16 kHz samples and clamps out-of-range values", () => {
    const result = resamplePcm16(new Float32Array([-2, -1, 0, 1, 2]), 16000);
    expect([...result]).toEqual([-32768, -32768, 0, 32767, 32767]);
  });

  it("returns empty PCM for an empty or invalid-rate chunk", () => {
    expect(resamplePcm16(new Float32Array(), 48000)).toHaveLength(0);
    expect(resamplePcm16(new Float32Array([0.1]), 0)).toHaveLength(0);
  });
});

describe("silence gate", () => {
  it("measures level", () => {
    expect(rms(new Float32Array(100))).toBe(0);
    expect(rms(new Float32Array(100).fill(0.5))).toBeCloseTo(0.5);
  });
  it("sends speech and a hangover, skips long silence, flushes once, then resumes with a lead-in", () => {
    const gate = new SilenceGate(0.01, 700, 1200);
    expect(gate.push(0, 0)).toEqual({ send: false, resumed: false, flush: false });
    expect(gate.push(0.2, 100)).toEqual({ send: true, resumed: true, flush: false });
    expect(gate.push(0.2, 200)).toEqual({ send: true, resumed: false, flush: false });
    expect(gate.push(0, 500).send).toBe(true);
    expect(gate.push(0, 1000)).toEqual({ send: false, resumed: false, flush: false });
    expect(gate.push(0, 1400)).toEqual({ send: false, resumed: false, flush: true });
    expect(gate.push(0, 1500)).toEqual({ send: false, resumed: false, flush: false });
    expect(gate.push(0.2, 3000)).toEqual({ send: true, resumed: true, flush: false });
  });
});
