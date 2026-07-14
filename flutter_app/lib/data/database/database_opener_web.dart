import 'package:sqlite3/wasm.dart';

Future<CommonDatabase> openDatabase() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(dbName: 'parlesprint');
  sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return sqlite.open('parlesprint.db');
}
