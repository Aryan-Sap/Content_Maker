import 'package:path/path.dart' as p;

class VideoAsset {
  const VideoAsset(this.path);

  final String path;

  bool get isEmpty => path.trim().isEmpty;

  String get fileName => p.basename(path);
}
