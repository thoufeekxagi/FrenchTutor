/// The learner profile row (single local row until auth exists). Onboarding
/// writes it; queue policy, Marie's language ratio, and reminders read it.
class Profile {
  Profile({
    required this.id,
    this.goal = 'tef_canada', // tef_canada | everyday | unsure
    this.level = 'zero', // zero | basics | conversational | unsure
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
