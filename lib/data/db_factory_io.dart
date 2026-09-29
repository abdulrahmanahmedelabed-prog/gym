import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// قاعدة البيانات على الجوال: ملف في مجلد التطبيق الخاص
/// على الجوال: مجلد التطبيق الخاص. على ويندوز: AppData (لا تختلط بمستندات المستخدم)
Future<Directory> _dataDir() async =>
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ? getApplicationSupportDirectory() : getApplicationDocumentsDirectory();

Future<Database> openGymDatabase(String name) async {
  final dir = await _dataDir();
  await Directory(dir.path).create(recursive: true);
  return databaseFactoryIo.openDatabase(p.join(dir.path, name));
}

/// مجلد النسخ الاحتياطية التلقائية
Future<String?> backupDirectory() async {
  final dir = await _dataDir();
  final d = Directory(p.join(dir.path, 'backups'));
  await d.create(recursive: true);
  return d.path;
}

Future<void> writeFile(String path, List<int> bytes) => File(path).writeAsBytes(bytes, flush: true);

Future<List<String>> listFiles(String dir) async =>
    Directory(dir).listSync().whereType<File>().map((f) => f.path).toList()..sort();

Future<void> deleteFile(String path) => File(path).delete();
