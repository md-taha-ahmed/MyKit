import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/rss/domain/entities/feed_article.dart';

FeedArticle _a(String link) =>
    FeedArticle(id: 'yt:video:x', feedId: 'f', title: 't', link: link);

void main() {
  test('Shorts are recognised by their link; ids come out of both forms', () {
    final short = _a('https://www.youtube.com/shorts/mND4T0lzg_g');
    final video = _a('https://www.youtube.com/watch?v=v9QtM6qnG50');
    expect(short.isShort, isTrue);
    expect(video.isShort, isFalse);
    expect(short.youtubeId, 'mND4T0lzg_g');
    expect(video.youtubeId, 'v9QtM6qnG50');
    expect(_a('https://example.com/shorts/x').youtubeId, isNull);
  });
}
