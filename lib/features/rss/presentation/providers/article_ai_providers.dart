import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/ai/gemini_client.dart';
import '../../data/datasources/article_text_source.dart';
import '../../domain/entities/feed_article.dart';
import 'offline_providers.dart';
import 'rss_providers.dart';

final articleTextSourceProvider = Provider<ArticleTextSource>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ArticleTextSource(client);
});

// ---------------------------------------------------------------------------
// Session: AI chats and briefings live in memory only
// ---------------------------------------------------------------------------

/// Bumped to forget every article chat and briefing: when MyKit is closed,
/// or after it has been in the background for [_forgetAfter].
final aiSessionProvider = NotifierProvider<AiSessionNotifier, int>(
  AiSessionNotifier.new,
);

class AiSessionNotifier extends Notifier<int> {
  static const _forgetAfter = Duration(minutes: 30);
  DateTime? _leftAt;

  @override
  int build() {
    final listener = AppLifecycleListener(
      onHide: () => _leftAt = DateTime.now(),
      onShow: () {
        final left = _leftAt;
        _leftAt = null;
        if (left != null && DateTime.now().difference(left) > _forgetAfter) {
          forget();
        }
      },
      onDetach: forget,
    );
    ref.onDispose(listener.dispose);
    return 0;
  }

  void forget() => state++;
}

// ---------------------------------------------------------------------------
// Article text, summary and background briefing
// ---------------------------------------------------------------------------

/// The fullest text we can get: a copy saved for offline reading, the
/// feed's own text, or the web page when the feed only has a teaser.
final articleTextProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  articleId,
) async {
  final article = ref.read(articleByIdProvider(articleId));
  if (article == null) throw const AiException('Article not found.');
  final saved = await ref.read(offlineStoreProvider).text(articleId);
  if (saved != null && saved.isNotEmpty) {
    ref.keepAlive();
    return saved;
  }
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
      ref.watch(aiSessionProvider);
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

/// The context the chat works from, prepared once per article: the full
/// text plus a background briefing researched with Google Search (who's
/// who, terms, what led here, why it matters, what's disputed).
class ArticleBriefing {
  const ArticleBriefing({
    required this.articleContext,
    required this.background,
    this.sources = const [],
    this.error,
  });

  /// Title, source, date, URL and the full article text.
  final String articleContext;

  /// Researched background (may be empty if preparing it failed).
  final String background;
  final List<AiSource> sources;

  /// Why the background couldn't be prepared (the chat still works).
  final String? error;
}

final articleBriefingProvider = FutureProvider.autoDispose
    .family<ArticleBriefing, String>((ref, articleId) async {
      ref.watch(aiSessionProvider);
      final article = ref.read(articleByIdProvider(articleId));
      if (article == null) throw const AiException('Article not found.');
      final text = await ref.watch(articleTextProvider(articleId).future);
      final feed = ref.read(rssLibraryProvider).feedById(article.feedId);
      final context = _articleContext(article, feed?.title, text);

      AiReply background;
      String? error;
      try {
        background = await ref
            .read(geminiClientProvider)
            .reply(
              system: _briefingPrompt,
              messages: [(fromUser: true, text: context)],
              temperature: 0.2,
              webSearch: true,
            );
      } on AiException catch (e) {
        // The chat still works from the article alone.
        background = const AiReply('');
        error = e.message;
      }
      ref.keepAlive();
      return ArticleBriefing(
        articleContext: context,
        background: background.text,
        sources: background.sources,
        error: error,
      );
    });

const _briefingPrompt = '''
You prepare a background briefing so that an assistant can help a reader
fully understand the news article below. Search the web for the context the
article assumes its readers already know. Write the briefing in the same
language as the article, as compact notes, with these sections:

1. Gist: 2-3 sentences on what happened.
2. Who and what: each person, organisation, place or product mentioned, in
   one line (who they are and their role here).
3. Terms: jargon, acronyms and concepts, explained in plain words.
4. Background and timeline: what led to this, with dates.
5. Why it matters: stakes and likely consequences.
6. Perspectives: where sides disagree or facts are contested.
7. Open questions the article leaves.

Be factual and specific (names, numbers, dates). Mark anything uncertain.
Do not repeat the article; add what it leaves out. 400-800 words.
If you cannot search, write from what you know and say how recent your
knowledge is.''';

String _chatPrompt(ArticleBriefing b) =>
    '''
You are a friendly, knowledgeable explainer. The user is reading the news
article below and wants to understand it and the world around it. You have
the full ARTICLE, a BACKGROUND briefing prepared for it, and you may search
the web for anything else.

How to answer:
- Reply in the language the user writes in (Arabic: Modern Standard Arabic
  unless they write in a dialect).
- Teach, don't just summarise: give context, history, causes, how things
  work, who the actors are and what it means for people. Explain jargon in
  plain words and use examples or analogies when they help.
- Long, detailed answers are welcome when the question calls for one; keep
  simple questions short. Use short headings and bullet points for longer
  answers.
- Make clear what the article says versus background knowledge. If facts
  are uncertain or contested, say so. Never invent quotes or numbers.
- Remember the whole conversation: follow-up questions build on earlier
  answers.
- End with one last line, exactly in this form, with three short follow-up
  questions the user might ask next, in their language:
FOLLOW_UPS: question one | question two | question three

ARTICLE
${b.articleContext}

BACKGROUND
${b.background.isEmpty ? '(Not available; rely on the article and search.)' : b.background}''';

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class ChatTurn {
  const ChatTurn({
    required this.fromUser,
    required this.text,
    this.sources = const [],
    this.followUps = const [],
  });

  final bool fromUser;
  final String text;
  final List<AiSource> sources;
  final List<String> followUps;
}

class ArticleChatState {
  const ArticleChatState({
    this.turns = const [],
    this.preparing = false,
    this.thinking = false,
    this.answering = false,
    this.error,
  });

  final List<ChatTurn> turns;

  /// Reading the article and researching background (first question).
  final bool preparing;

  /// Waiting for the answer to start.
  final bool thinking;

  /// The last turn is an answer still being written.
  final bool answering;
  final String? error;

  bool get busy => preparing || thinking || answering;

  ArticleChatState copyWith({
    List<ChatTurn>? turns,
    bool? preparing,
    bool? thinking,
    bool? answering,
    String? Function()? error,
  }) => ArticleChatState(
    turns: turns ?? this.turns,
    preparing: preparing ?? this.preparing,
    thinking: thinking ?? this.thinking,
    answering: answering ?? this.answering,
    error: error != null ? error() : this.error,
  );
}

/// Chat about one article, with the prepared briefing as context. Kept in
/// memory for the session (see [aiSessionProvider]).
final articleChatProvider = NotifierProvider.autoDispose
    .family<ArticleChatNotifier, ArticleChatState, String>(
      ArticleChatNotifier.new,
    );

class ArticleChatNotifier extends Notifier<ArticleChatState> {
  ArticleChatNotifier(this.articleId);

  final String articleId;

  /// Changes when the chat is cleared, so a running answer stops writing.
  int _generation = 0;

  @override
  ArticleChatState build() {
    ref.watch(aiSessionProvider);
    // Keep the conversation while the user goes back and forth.
    ref.keepAlive();
    _generation++;
    return const ArticleChatState();
  }

  /// Starts preparing the context before the first question is typed.
  void prepare() =>
      ref.read(articleBriefingProvider(articleId).future).ignore();

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;
    final generation = _generation;
    bool live() => generation == _generation;

    final history = [...state.turns, ChatTurn(fromUser: true, text: q)];
    state = state.copyWith(
      turns: history,
      preparing:
          !ref.exists(articleBriefingProvider(articleId)) ||
          ref.read(articleBriefingProvider(articleId)).isLoading,
      thinking: true,
      error: () => null,
    );
    try {
      final briefing = await ref.read(
        articleBriefingProvider(articleId).future,
      );
      if (!live()) return;
      state = state.copyWith(preparing: false);

      final stream = ref
          .read(geminiClientProvider)
          .streamReply(
            system: _chatPrompt(briefing),
            messages: [
              for (final t in history) (fromUser: t.fromUser, text: t.text),
            ],
            webSearch: true,
          );
      AiReply? last;
      await for (final reply in stream) {
        if (!live()) return;
        last = reply;
        state = state.copyWith(
          turns: [
            ...history,
            ChatTurn(
              fromUser: false,
              text: visibleAnswer(reply.text),
              sources: reply.sources,
            ),
          ],
          thinking: false,
          answering: true,
        );
      }
      if (!live() || last == null) return;
      final (body, followUps) = splitFollowUps(last.text);
      state = state.copyWith(
        turns: [
          ...history,
          ChatTurn(
            fromUser: false,
            text: body,
            sources: last.sources,
            followUps: followUps,
          ),
        ],
        thinking: false,
        answering: false,
      );
    } catch (e) {
      if (!live()) return;
      state = state.copyWith(
        turns: history,
        preparing: false,
        thinking: false,
        answering: false,
        error: () => '$e',
      );
    }
  }

  /// Drops the failed question so it can be asked again.
  String? retryLast() {
    final last = state.turns.lastOrNull;
    if (last == null || !last.fromUser) return null;
    state = state.copyWith(
      turns: state.turns.sublist(0, state.turns.length - 1),
      error: () => null,
    );
    return last.text;
  }

  void clear() {
    _generation++;
    state = const ArticleChatState();
  }
}

final _followUpsLine = RegExp(
  r'^\s*\**\s*FOLLOW[_ -]?UPS?\s*\**\s*:',
  caseSensitive: false,
);

/// Splits the model's answer from its trailing `FOLLOW_UPS: a | b | c` line.
(String, List<String>) splitFollowUps(String text) {
  final lines = text.split('\n');
  final i = lines.lastIndexWhere(_followUpsLine.hasMatch);
  if (i < 0) return (text.trim(), const []);
  final items = lines[i]
      .replaceFirst(_followUpsLine, '')
      .split('|')
      .map((q) => q.replaceAll('*', '').trim())
      .where((q) => q.isNotEmpty)
      .take(3)
      .toList();
  return (lines.sublist(0, i).join('\n').trim(), items);
}

/// What to show while the answer streams: without the follow-ups line, even
/// when it has only partly arrived ("FOLL…").
String visibleAnswer(String text) {
  final (body, _) = splitFollowUps(text);
  if (body != text.trim()) return body;
  final lines = text.trimRight().split('\n');
  final tail = lines.last.trim().replaceAll('*', '').toUpperCase();
  if (tail.isNotEmpty && 'FOLLOW_UPS:'.startsWith(tail)) {
    return lines.sublist(0, lines.length - 1).join('\n').trim();
  }
  return text.trim();
}
