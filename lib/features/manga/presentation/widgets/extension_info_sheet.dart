import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'manga_widgets.dart';

/// One website an extension reads from, with the languages it serves.
typedef ExtensionSite = ({String url, String name, List<String> langs});

/// Groups sources by website (multi-language extensions often share one site).
List<ExtensionSite> groupSites(
  Iterable<({String name, String lang, String url})> sources,
) {
  final byUrl = <String, ({String name, List<String> langs})>{};
  for (final s in sources) {
    final url = s.url.trim();
    if (url.isEmpty) continue;
    final entry = byUrl[url];
    if (entry == null) {
      byUrl[url] = (name: s.name, langs: [s.lang]);
    } else if (!entry.langs.contains(s.lang)) {
      entry.langs.add(s.lang);
    }
  }
  return [
    for (final e in byUrl.entries)
      (url: e.key, name: e.value.name, langs: e.value.langs),
  ];
}

/// Details of an extension with links to its websites, so the user can
/// check a site before installing.
Future<void> showExtensionInfoSheet(
  BuildContext context, {
  required String name,
  required String? iconUrl,
  required String versionName,
  required String lang,
  required bool nsfw,
  required List<ExtensionSite> sites,
  String? note,
  VoidCallback? onInstall,
  String installLabel = 'Install',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: sites.length > 4 ? .7 : .5,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 56,
                  child: iconUrl == null
                      ? const Icon(Icons.extension, size: 32)
                      : Image.network(
                          iconUrl,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.extension, size: 32),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      [
                        'v$versionName',
                        languageName(lang),
                        if (nsfw) '18+',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(note, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 20),
          Text(
            sites.length == 1 ? 'Website' : 'Websites · ${sites.length}',
            style: const TextStyle(
              color: mangaAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (sites.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'This extension doesn\'t list a website.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          for (final site in sites)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: Text(
                Uri.tryParse(site.url)?.host ?? site.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (site.name != name) site.name,
                  site.langs.map(languageName).join(', '),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () => launchUrl(
                Uri.parse(site.url),
                mode: LaunchMode.externalApplication,
              ),
            ),
          if (onInstall != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: mangaAccent),
              onPressed: () {
                Navigator.pop(context);
                onInstall();
              },
              icon: const Icon(Icons.download),
              label: Text(installLabel),
            ),
          ],
        ],
      ),
    ),
  );
}
