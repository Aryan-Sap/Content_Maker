import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class AppPaths {
  static Future<String> newProjectFile() async {
    final root = await getApplicationDocumentsDirectory();
    return p.join(
      root.path,
      'Content Maker',
      'projects',
      'project_${DateTime.now().microsecondsSinceEpoch}.cmproj',
    );
  }
}
