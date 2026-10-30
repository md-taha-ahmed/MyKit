import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/offline_providers.dart';

/// An article image: the copy saved for offline reading when there is one,
/// otherwise from the network.
class FeedImage extends ConsumerWidget {
  const FeedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.cacheWidth,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when a download finishes so new copies are picked up.
    ref.watch(offlineDownloadProvider.select((s) => s.savedCount));
    final file = ref.read(offlineStoreProvider).image(url);
    final onError = errorBuilder ?? (_, _, _) => const SizedBox.shrink();
    return file != null
        ? Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            cacheWidth: cacheWidth,
            errorBuilder: onError,
          )
        : Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            cacheWidth: cacheWidth,
            errorBuilder: onError,
          );
  }
}
