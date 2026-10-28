/// A YouTube channel the user is subscribed to.
class YoutubeChannel {
  const YoutubeChannel({
    required this.id,
    required this.title,
    this.description = '',
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String description;
  final String? thumbnailUrl;

  /// The channel's public RSS feed (latest ~15 uploads, no API quota).
  String get feedUrl =>
      'https://www.youtube.com/feeds/videos.xml?channel_id=$id';
}
