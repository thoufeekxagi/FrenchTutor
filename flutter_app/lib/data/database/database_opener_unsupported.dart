import 'package:sqlite3/common.dart';

Future<CommonDatabase> openDatabase() {
  throw UnsupportedError('SQLite is unavailable on this platform.');
}
