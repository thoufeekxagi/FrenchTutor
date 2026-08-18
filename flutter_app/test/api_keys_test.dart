import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/config/api_keys.dart';

void main() {
  test('ships public Supabase configuration for direct Xcode builds', () {
    expect(ApiKeys.supabaseUrl, startsWith('https://'));
    expect(ApiKeys.supabaseAnonKey, startsWith('sb_publishable_'));
  });
}
