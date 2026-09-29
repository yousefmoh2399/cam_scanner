import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

class LocalMediaStorageService {
  const LocalMediaStorageService();

  Future<Directory> scansDirectory() async {
    final appDir = await path_provider.getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, 'Scans'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> documentsDirectory() => scansDirectory();

  Future<Directory> pagesDirectory() async {
    final appDir = await path_provider.getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, 'Pages'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> exportsDirectory() async {
    final appDir = await path_provider.getApplicationDocumentsDirectory();
    final dir = Directory(path.join(appDir.path, 'Exports'));
    await dir.create(recursive: true);
    return dir;
  }
}
