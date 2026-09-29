import 'package:sembast_web/sembast_web.dart';

/// على المتصفح: IndexedDB
Future<Database> openGymDatabase(String name) => databaseFactoryWeb.openDatabase(name);

Future<String?> backupDirectory() async => null;

Future<void> writeFile(String path, List<int> bytes) async {}

Future<List<String>> listFiles(String dir) async => [];

Future<void> deleteFile(String path) async {}
