import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/publishing/publish_metadata.dart';

void main() {
  test('rejects an empty title', () {
    const metadata = PublishMetadata(title: '   ');
    expect(metadata.validate(), isNotNull);
  });

  test('rejects a title over the length limit', () {
    final metadata = PublishMetadata(title: 'a' * 101);
    expect(metadata.validate(), isNotNull);
  });

  test('accepts a valid title', () {
    const metadata = PublishMetadata(title: 'Clutch ace');
    expect(metadata.validate(), isNull);
  });

  test('builds a caption with description and normalized hashtags', () {
    const metadata = PublishMetadata(
      title: 'Clutch ace',
      description: 'Ranked highlight',
      hashtags: ['#gaming', 'valorant', '  '],
    );

    expect(
      metadata.caption,
      'Clutch ace\nRanked highlight\n#gaming #valorant',
    );
  });
}
