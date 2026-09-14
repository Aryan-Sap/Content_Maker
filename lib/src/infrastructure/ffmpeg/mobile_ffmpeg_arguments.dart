/// Returns a mutable mobile command copy.
///
/// The full mobile engine includes the filters and x264 encoder used by the
/// desktop graph, so Android and iOS can use the same composition and codec.
abstract final class MobileFfmpegArguments {
  static List<String> adapt(List<String> arguments) {
    return List<String>.of(arguments);
  }
}
