import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

Future<CommonDatabase> openDatabase() async {
  final documents = await getApplicationDocumentsDirectory();
  return sqlite3.open(path.join(documents.path, 'french_tutor.db'));
}
