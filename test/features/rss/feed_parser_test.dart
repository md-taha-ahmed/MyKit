import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/rss/data/parsers/feed_parser.dart';
import 'package:mykit/features/rss/data/parsers/html_text.dart';

void main() {
  test('RSS 2.0 with atom:link, content:encoded and media', () {
    const xml = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"
     xmlns:content="http://purl.org/rss/1.0/modules/content/"
     xmlns:media="http://search.yahoo.com/mrss/"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <atom:link href="https://ex.com/feed" rel="self"/>
    <title>Example &amp; Co</title>
    <link>https://ex.com</link>
    <item>
      <title>Hello <![CDATA[World]]></title>
      <link>https://ex.com/a</link>
      <guid>abc-1</guid>
      <pubDate>Tue, 27 Oct 2026 06:00:00 +0300</pubDate>
      <dc:creator>Taha</dc:creator>
      <description>Short &lt;b&gt;teaser&lt;/b&gt;</description>
      <content:encoded><![CDATA[<p>First para</p><p>Second &amp; last</p>]]></content:encoded>
      <media:thumbnail url="https://ex.com/t.jpg"/>
    </item>
  </channel>
</rss>''';
    final feed = FeedParser.tryParse(xml)!;
    expect(feed.title, 'Example & Co');
    expect(feed.siteUrl, 'https://ex.com');
    final a = feed.articles.single;
    expect(a.id, 'abc-1');
    expect(a.title, 'Hello World');
    expect(a.summary, 'Short teaser');
    expect(a.content, 'First para\n\nSecond & last');
    expect(a.imageUrl, 'https://ex.com/t.jpg');
    expect(a.author, 'Taha');
    expect(a.publishedAt!.toUtc(), DateTime.utc(2026, 10, 27, 3));
  });

  test('Atom', () {
    const xml = '''<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Blog</title>
  <link rel="self" href="https://b.com/atom.xml"/>
  <link href="https://b.com/"/>
  <entry>
    <id>urn:1</id>
    <title type="html">Post</title>
    <link rel="alternate" href="https://b.com/post"/>
    <updated>2026-10-20T10:00:00Z</updated>
    <author><name>Ann</name></author>
    <content type="html">&lt;img src="https://b.com/i.png"&gt;Body</content>
  </entry>
</feed>''';
    final feed = FeedParser.tryParse(xml)!;
    expect(feed.siteUrl, 'https://b.com/');
    final a = feed.articles.single;
    expect(a.link, 'https://b.com/post');
    expect(a.author, 'Ann');
    expect(a.imageUrl, 'https://b.com/i.png');
    expect(a.content, 'Body');
    expect(a.publishedAt!.toUtc(), DateTime.utc(2026, 10, 20, 10));
  });

  test('RSS 1.0 (RDF) items live beside the channel', () {
    const xml =
        '''<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns="http://purl.org/rss/1.0/">
  <channel><title>RDF</title><link>https://r.com</link></channel>
  <item><title>One</title><link>https://r.com/1</link></item>
  <item><title>Two</title><link>https://r.com/2</link></item>
</rdf:RDF>''';
    final feed = FeedParser.tryParse(xml)!;
    expect(feed.title, 'RDF');
    expect(feed.articles.map((a) => a.title), ['One', 'Two']);
  });

  test('prefers the largest image', () {
    const xml = '''<rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
  <title>T</title>
  <item>
    <title>A</title>
    <media:thumbnail url="https://x/small.jpg" width="240"/>
    <media:thumbnail url="https://x/medium.jpg" width="640"/>
    <media:content url="https://x/full.jpg" medium="image" width="1200"/>
  </item>
  <item>
    <title>B</title>
    <media:thumbnail url="https://x/small.jpg" width="240"/>
    <media:thumbnail url="https://x/medium.jpg" width="640"/>
  </item>
</channel></rss>''';
    final feed = FeedParser.tryParse(xml)!;
    expect(feed.articles[0].imageUrl, 'https://x/full.jpg');
    expect(feed.articles[1].imageUrl, 'https://x/medium.jpg');
  });

  test('HTML pages are not feeds', () {
    expect(FeedParser.tryParse('<html><body>hi</body></html>'), isNull);
    expect(FeedParser.tryParse('not xml at all'), isNull);
  });

  test('entities and truncation', () {
    expect(HtmlText.decodeEntities('&#8217;&#x2014;&hellip;'), '’—…');
    expect(HtmlText.truncate('one two three four', 10), 'one two…');
  });
}
