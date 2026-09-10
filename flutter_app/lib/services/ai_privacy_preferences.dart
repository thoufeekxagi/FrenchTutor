import 'package:shared_preferences/shared_preferences.dart';

/// Local, device-scoped controls for the AI disclosures shown in the app.
///
/// This deliberately stays separate from lesson storage and the Supabase
/// schema. Consent is a device-level choice, so changing it never changes a
/// learner's course, practice history, or generated lessons.
abstract final class AiPrivacyPreferences {
  static const consentVersion = 'v2';
  static const consentKey = 'ai_data_consent_v2';
  static const consentedAtKey = 'ai_data_consent_v2_at';
  static const voiceKey = 'ai_data_voice_v2';
  static const textKey = 'ai_data_text_v2';
  static const mediaKey = 'ai_data_media_v2';

  static Future<bool> hasConsented() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentKey) == true;
  }

  static Future<bool> canUseVoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentKey) == true && prefs.getBool(voiceKey) == true;
  }

  static Future<AiPrivacySnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    return AiPrivacySnapshot(
      voice: prefs.getBool(voiceKey) ?? false,
      text: prefs.getBool(textKey) ?? false,
      media: prefs.getBool(mediaKey) ?? false,
      consentedAt: prefs.getString(consentedAtKey),
    );
  }

  static Future<void> acceptAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, true);
    await prefs.setString(
      consentedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    await prefs.setBool(voiceKey, true);
    await prefs.setBool(textKey, true);
    await prefs.setBool(mediaKey, true);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, false);
    await prefs.setBool(voiceKey, false);
    await prefs.setBool(textKey, false);
    await prefs.setBool(mediaKey, false);
  }
}

class AiPrivacySnapshot {
  const AiPrivacySnapshot({
    required this.voice,
    required this.text,
    required this.media,
    required this.consentedAt,
  });

  final bool voice;
  final bool text;
  final bool media;
  final String? consentedAt;
}
