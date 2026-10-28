import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-private documents directory (survives app updates, removed on uninstall).
///
/// Resolved once in `main()` and injected via a `ProviderScope` override.
final appDocumentsDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'appDocumentsDirectoryProvider must be overridden in main()',
  ),
);
