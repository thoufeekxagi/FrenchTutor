/// The learner profile row (single local row until auth exists). Onboarding
/// writes it; queue policy, the tutor's language ratio, and reminders read it.
class Profile {
  Profile({
    required this.id,
    this.goal = 'tef_canada', // tef_canada | everyday | unsure
    this.level = 'zero', // CEFR 'a1'|'a2'|'b1'|'b2', or legacy values (see LearnerLevel)
    this.sessionLength = 'standard', // quick | standard | deep
    this.reminderTime,
    this.onboardedAt,
  });

  final String id;
  String goal;
  String level;
  String sessionLength;
  String? reminderTime; // 'HH:mm'
  DateTime? onboardedAt;

  bool get isOnboarded => onboardedAt != null;
}

/// The level vocabulary, old and new, in one place. Onboarding v2 writes CEFR
/// values ('a1'..'b2'); profiles created before that hold the legacy values
/// ('zero' | 'basics' | 'conversational' | 'unsure'). Every consumer reads
/// through these helpers so BOTH vocabularies keep working forever — no data
/// migration, no crash on an old install.
class LearnerLevel {
  LearnerLevel._();

  static const cefrValues = ['a1', 'a2', 'b1', 'b2'];

  /// Can this learner hold a simple conversation? Drives the tutor's
  /// French-led vs English-led register.
  static bool isConversational(String level) => switch (level) {
    'b1' || 'b2' || 'conversational' => true,
    _ => false,
  };

  /// Default English/French mix for a level (P2.3) — beginners get gentle
  /// scaffolding, B2 gets immersion. Used to derive the mix at onboarding so
  /// it never has to be its own question.
  static String defaultLanguageMix(String level) => switch (level) {
    'b2' => 'immersive',
    'b1' || 'conversational' => 'balanced',
    _ => 'gentle',
  };

  /// Short display label ("A1", "B2", or a readable legacy name).
  static String displayLabel(String level) => switch (level) {
    'a1' => 'A1',
    'a2' => 'A2',
    'b1' => 'B1',
    'b2' => 'B2',
    'zero' => 'Beginner',
    'basics' => 'Basics',
    'conversational' => 'Conversational',
    _ => 'Exploring',
  };
}
