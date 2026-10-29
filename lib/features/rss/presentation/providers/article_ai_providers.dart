import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/ai/gemini_client.dart';
import '../../data/datasources/article_text_source.dart';
import '../../domain/entities/feed_article.dart';
import 'rss_providers.dart';

final articleTextSourceProvider = Provider<ArticleTextSource>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ArticleTextSource(client);
});

/// The fullest text we can get: the feed's own text, or the web page when the
/// feed only has a teaser.
final articleTextProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  articleId,
) async {
  final article = ref.read(articleByIdProvider(articleId));
  if (article == null) throw const AiException('Article not found.');
  final own = article.content.isNotEmpty ? article.content : article.summary;
  final link = article.link;
  final isVideo = link != null && link.contains('youtube.com');
  if (own.length < 1500 && link != null && !isVideo) {
    final page = await ref.read(articleTextSourceProvider).fetch(link);
    if (page != null && page.length > own.length) {
      ref.keepAlive();
      return page;
    }
  }
  ref.keepAlive();
  return own;
});

String _articleContext(FeedArticle article, String? feedTitle, String text) =>
    '''
Title: ${article.title}
Source: ${feedTitle ?? 'unknown'}
${article.publishedAt != null ? 'Published: ${article.publishedAt!.toIso8601String().substring(0, 10)}\n' : ''}URL: ${article.link ?? 'n/a'}

${text.isEmpty ? '(The feed only provides the headline.)' : text}''';

/// A short summary of an article, made once and kept for the session.
final articleSummaryProvider = FutureProvider.autoDispose
    .family<String, String>((ref, articleId) async {
      final article = ref.read(articleByIdProvider(articleId));
      if (article == null) throw const AiException('Article not found.');
      final text = await ref.watch(articleTextProvider(articleId).future);
      final feed = ref.read(rssLibraryProvider).feedById(article.feedId);
      final summary = await ref
          .read(geminiClientProvider)
          .generate(
            system:
                'You summarise news articles and videos for a busy reader. '
                'Write in the same language as the article. Start with one '
                'sentence giving the gist, then 3-6 short bullet points with '
                'the key facts (names, numbers, dates). No preamble. If only '
                'a headline is available, say so briefly and summarise what '
                'the headline states.',
            messages: [
              (
                fromUser: true,
                text: _articleContext(article, feed?.title, text),
              ),
            ],
            temperature: 0.2,
          );
      ref.keepAlive();
      return summary;
    });

/// Chat about one article; the article is the model's context.
final articleChatProvider = NotifierProvider.autoDispose
    .family<ArticleChatNotifier, ArticleChatState, String>(
      ArticleChatNotifier.new,
    );

typedef ArticleChatState = ({
  List<AiMessage> messages,
  bool thinking,
  String? error,
});

class ArticleChatNotifier extends Notifier<ArticleChatState> {
  ArticleChatNotifier(this.articleId);

  final String articleId;

  @override
  ArticleChatState build() {
    // Keep the conversation while the user goes back and forth.
    ref.keepAlive();
    return (messages: const [], thinking: false, error: null);
  }

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.thinking) return;
    final messages = [...state.messages, (fromUser: true, text: q)];
    state = (messages: messages, thinking: true, error: null);
    try {
      final article = ref.read(articleByIdProvider(articleId));
      if (article == null) throw const AiException('Article not found.');
      final text = await ref.read(articleTextProvider(articleId).future);
      final feed = ref.read(rssLibraryProvider).feedById(article.feedId);
      final answer = await ref
          .read(geminiClientProvider)
          .generate(
            system:
                'You help the user understand one article. Answer questions '
                'about it clearly and briefly, in the language the user '
                'writes in. Base answers on the article; when you add '
                'general background knowledge, say so. If the article does '
                'not cover something, say that instead of guessing.\n\n'
                'ARTICLE\n${_articleContext(article, feed?.title, text)}',
            messages: messages,
          );
      state = (
        messages: [...messages, (fromUser: false, text: answer)],
        thinking: false,
        error: null,
      );
    } catch (e) {
      state = (messages: messages, thinking: false, error: '$e');
    }
  }

  /// Drops the failed question so it can be asked again.
  String? retryLast() {
    final last = state.messages.lastOrNull;
    if (last == null || !last.fromUser) return null;
    state = (
      messages: state.messages.sublist(0, state.messages.length - 1),
      thinking: false,
      error: null,
    );
    return last.text;
  }

  void clear() => state = (messages: const [], thinking: false, error: null);
}
