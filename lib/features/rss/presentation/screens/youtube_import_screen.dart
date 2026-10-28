import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/youtube_channel.dart';
import '../providers/rss_providers.dart';

const _youtubeRed = Color(0xFFFF3B30);

/// Sign in with Google, pick subscribed channels, add their RSS feeds.
class YoutubeImportScreen extends ConsumerStatefulWidget {
  const YoutubeImportScreen({super.key});

  @override
  ConsumerState<YoutubeImportScreen> createState() =>
      _YoutubeImportScreenState();
}

class _YoutubeImportScreenState extends ConsumerState<YoutubeImportScreen> {
  List<YoutubeChannel>? _channels;
  final _selected = <String>{};
  String _query = '';
  bool _loading = false;
  bool _adding = false;
  String? _error;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    // Already signed in before: load straight away (token refreshes silently).
    final repo = ref.read(rssRepositoryProvider);
    if (repo.youtubeConfigured && repo.youtubeSignedIn) {
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channels = await ref
          .read(rssRepositoryProvider)
          .youtubeSubscriptions();
      if (!mounted) return;
      setState(() => _channels = channels);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCategory() async {
    const newCategory = '__new__';
    final categories = ref.read(rssLibraryProvider).categories;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to category'),
        children: [
          for (final c in categories)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.pop(context, c.id),
              child: Text(c.name, style: const TextStyle(fontSize: 16)),
            ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.pop(context, newCategory),
            child: const Row(
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 12),
                Text('New category…', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice != newCategory) {
      setState(() => _categoryId = choice);
      return;
    }
    final name = await showTextInputDialog(
      context,
      title: 'New category',
      initialValue: 'YouTube',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    final category = await ref
        .read(rssLibraryProvider.notifier)
        .addCategory(name);
    if (mounted) setState(() => _categoryId = category.id);
  }

  Future<void> _add() async {
    final channels = _channels!.where((c) => _selected.contains(c.id));
    final categoryId =
        _categoryId ?? ref.read(rssLibraryProvider).categories.first.id;
    setState(() => _adding = true);
    final count = await ref.read(rssLibraryProvider.notifier).addFeedsBulk([
      for (final c in channels)
        (
          url: c.feedUrl,
          title: c.title,
          siteUrl: 'https://www.youtube.com/channel/${c.id}',
        ),
    ], categoryId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added $count ${count == 1 ? 'channel' : 'channels'}. '
          'Loading their videos…',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _disconnect() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Disconnect Google account?',
      message:
          'MyKit loses access to your YouTube subscriptions. Channels you '
          'already added stay in your feeds.',
      confirmLabel: 'Disconnect',
    );
    if (!ok) return;
    await ref.read(rssRepositoryProvider).disconnectYoutube();
    if (mounted) {
      setState(() {
        _channels = null;
        _selected.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(rssLibraryProvider);
    final followed = library.feeds.map((f) => f.url).toSet();
    final channels = _channels;
    final category =
        library.categoryById(_categoryId ?? '') ?? library.categories.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube subscriptions'),
        actions: [
          if (channels != null)
            PopupMenuButton<String>(
              onSelected: (_) => _disconnect(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Disconnect Google account'),
                ),
              ],
            ),
        ],
      ),
      body: channels == null && _loading && _error == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _youtubeRed),
                  SizedBox(height: 16),
                  Text(
                    'Loading your subscriptions…',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            )
          : channels == null
          ? !ref.read(rssRepositoryProvider).youtubeConfigured
                ? _SetupForm(
                    onSaved: (id, secret) async {
                      await ref
                          .read(rssRepositoryProvider)
                          .configureYoutube(id, secret);
                      if (mounted) setState(() {});
                    },
                  )
                : _Intro(loading: _loading, error: _error, onContinue: _load)
          : _list(channels, followed),
      bottomNavigationBar: channels == null || channels.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _adding ? null : _pickCategory,
                        icon: const Icon(Icons.folder_outlined),
                        label: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _youtubeRed,
                        ),
                        onPressed: _selected.isEmpty || _adding ? null : _add,
                        child: Text(
                          _selected.isEmpty
                              ? 'Select channels'
                              : 'Add ${_selected.length}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _list(List<YoutubeChannel> channels, Set<String> followed) {
    if (channels.isEmpty) {
      return const Center(
        child: Text(
          'This account has no subscriptions.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    final q = _query.toLowerCase();
    final shown = channels
        .where((c) => q.isEmpty || c.title.toLowerCase().contains(q))
        .toList();
    final selectable = shown
        .where((c) => !followed.contains(c.feedUrl))
        .map((c) => c.id)
        .toSet();
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search your subscriptions',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${channels.length} subscriptions · '
                  '${_selected.length} selected',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: selectable.isEmpty
                    ? null
                    : () => setState(() {
                        allSelected
                            ? _selected.removeAll(selectable)
                            : _selected.addAll(selectable);
                      }),
                child: Text(allSelected ? 'Select none' : 'Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final c = shown[i];
              final added = followed.contains(c.feedUrl);
              return CheckboxListTile(
                value: added || _selected.contains(c.id),
                onChanged: added
                    ? null
                    : (v) => setState(
                        () => v == true
                            ? _selected.add(c.id)
                            : _selected.remove(c.id),
                      ),
                secondary: CircleAvatar(
                  backgroundColor: Colors.white10,
                  foregroundImage: c.thumbnailUrl == null
                      ? null
                      : NetworkImage(c.thumbnailUrl!),
                  child: Text(c.title.characters.first.toUpperCase()),
                ),
                title: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  added
                      ? 'Already in your feeds'
                      : c.description.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: added ? Colors.greenAccent : Colors.white54,
                    fontSize: 12.5,
                  ),
                ),
                activeColor: _youtubeRed,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.loading,
    required this.error,
    required this.onContinue,
  });

  final bool loading;
  final String? error;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.subscriptions, size: 72, color: _youtubeRed),
        const SizedBox(height: 16),
        Text(
          'Bring your YouTube channels',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Sign in with Google to see your subscriptions, then choose which '
          'channels to follow here. New uploads arrive through each channel\'s '
          'RSS feed — no algorithm, no recommendations.\n\n'
          'Your browser opens to sign in (works with microG). MyKit only asks '
          'for read-only access and never changes your YouTube account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, height: 1.4),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: loading ? null : onContinue,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_circle),
          label: Text(
            loading ? 'Loading subscriptions…' : 'Continue with Google',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.orangeAccent),
          ),
        ],
      ],
    );
  }
}

/// One-time entry of the Google Cloud "Desktop app" OAuth client.
class _SetupForm extends StatefulWidget {
  const _SetupForm({required this.onSaved});

  final Future<void> Function(String clientId, String clientSecret) onSaved;

  @override
  State<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends State<_SetupForm> {
  final _id = TextEditingController();
  final _secret = TextEditingController();

  static const _docs =
      'https://github.com/md-taha-ahmed/MyKit#youtube-subscriptions-import';

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _valid =>
      _id.text.trim().endsWith('.apps.googleusercontent.com') &&
      _secret.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.vpn_key_outlined, size: 56, color: _youtubeRed),
        const SizedBox(height: 12),
        Text(
          'Connect a Google API client',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'One-time setup: create a free "Desktop app" OAuth client in Google '
          'Cloud with the YouTube Data API enabled, then paste its ID and '
          'secret here. They stay on this phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, height: 1.4),
        ),
        TextButton.icon(
          onPressed: () =>
              launchUrl(Uri.parse(_docs), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.help_outline),
          label: const Text('Step-by-step guide'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _id,
          decoration: const InputDecoration(
            labelText: 'Client ID',
            hintText: '…apps.googleusercontent.com',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _secret,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Client secret'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _valid
              ? () => widget.onSaved(_id.text, _secret.text)
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
