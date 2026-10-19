import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/v3_cloud_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tutor chosen in onboarding stays until the learner changes it in
/// Settings, survives a restart, and follows the learner to a new phone.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ActiveTutor.onSaved = null;
    ActiveTutor.notifier.value = TutorPersona.marie;
  });

  test('a chosen tutor is saved and comes back after a restart', () async {
    await ActiveTutor.set(TutorPersona.byId('mathieu'));
    expect(ActiveTutor.current.voiceName, 'Orus');

    ActiveTutor.notifier.value = TutorPersona.marie; // a fresh launch
    await ActiveTutor.load();
    expect(ActiveTutor.current.id, 'mathieu');
    expect(ActiveTutor.current.displayName, 'Mathieu');
  });

  test('changing it in Settings replaces it and sticks', () async {
    await ActiveTutor.set(TutorPersona.byId('mathieu'));
    await ActiveTutor.set(TutorPersona.byId('camille'));
    ActiveTutor.notifier.value = TutorPersona.marie;
    await ActiveTutor.load();
    expect(ActiveTutor.current.id, 'camille');
  });

  test(
    'every choice is announced so it can be copied to the account',
    () async {
      var saved = 0;
      ActiveTutor.onSaved = () => saved++;
      await ActiveTutor.set(TutorPersona.byId('julien'));
      await ActiveTutor.set(TutorPersona.byId('marie'));
      expect(saved, 2);
    },
  );

  test('the tutor is part of the account data and the newest choice wins', () {
    final spec = V3CloudState.specs.firstWhere(
      (s) => s.key == 'tutor_persona_id',
    );
    expect(spec.kind, V3StateKind.scalar);
    final old = DateTime.utc(2026, 10, 1);
    final recent = DateTime.utc(2026, 10, 18);
    expect(
      V3CloudState.merge(
        spec.kind,
        'marie',
        'mathieu',
        localAt: old,
        remoteAt: recent,
      ),
      'mathieu',
      reason: 'a new phone takes the account choice',
    );
    expect(
      V3CloudState.merge(
        spec.kind,
        'camille',
        'mathieu',
        localAt: recent,
        remoteAt: old,
      ),
      'camille',
      reason: 'a fresh choice on this phone beats an older account one',
    );
    expect(V3CloudState.merge(spec.kind, null, 'julien'), 'julien');
    expect(V3CloudState.merge(spec.kind, 'julien', null), 'julien');
  });

  test('marking a change stamps the time even when signed out', () async {
    V3CloudState.markChanged('tutor_persona_id');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tutor_persona_id.__at'), isNotNull);
  });

  test('each tutor keeps its own distinct voice', () {
    final voices = TutorPersona.all.map((p) => p.voiceName).toList();
    expect(voices, ['Aoede', 'Puck', 'Leda', 'Orus']);
    expect(voices.toSet(), hasLength(4));
  });
}
