import 'dart:typed_data';

/// Wraps signed 16-bit little-endian PCM in a standard RIFF/WAV container.
/// Gemini Live returns raw PCM; native players need the header to determine
/// the sample rate, channel count, and frame format.
Uint8List pcm16ToWav(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  if (pcm.length.isOdd) {
    throw ArgumentError.value(
      pcm.length,
      'pcm',
      'must contain complete samples',
    );
  }
  if (sampleRate <= 0) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
  }
  if (channels <= 0) {
    throw ArgumentError.value(channels, 'channels', 'must be positive');
  }

  const bytesPerSample = 2;
  final blockAlign = channels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final output = Uint8List(44 + pcm.length);
  final view = ByteData.sublistView(output);

  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      output[offset + index] = value.codeUnitAt(index);
    }
  }

  writeAscii(0, 'RIFF');
  view.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM format
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bytesPerSample * 8, Endian.little);
  writeAscii(36, 'data');
  view.setUint32(40, pcm.length, Endian.little);
  output.setRange(44, output.length, pcm);
  return output;
}
