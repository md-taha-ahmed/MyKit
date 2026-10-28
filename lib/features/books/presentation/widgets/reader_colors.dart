import 'package:flutter/material.dart';

import '../../domain/entities/book.dart';

/// How pages are recoloured for each [ReaderColorMode].
///
/// The filter is applied to the whole viewer (pages + gaps), so
/// [viewerBackground] is chosen to still look dark *after* filtering.
class ReaderColors {
  const ReaderColors._(this.filter, this.viewerBackground, this.pageShadow);

  /// null = show the PDF as-is.
  final ColorFilter? filter;
  final Color viewerBackground;
  final bool pageShadow;

  static ReaderColors of(ReaderColorMode mode) => switch (mode) {
    ReaderColorMode.light => const ReaderColors._(
      null,
      Color(0xFF2B2B2E),
      true,
    ),
    // Inverted, softened: white paper → #0D0D0D, black ink → #E6E6E6.
    ReaderColorMode.dark => const ReaderColors._(
      ColorFilter.matrix(<double>[
        -0.85, 0, 0, 0, 230, //
        0, -0.85, 0, 0, 230,
        0, 0, -0.85, 0, 230,
        0, 0, 0, 1, 0,
      ]),
      // Light grey that the inversion turns into a dark gutter.
      Color(0xFFE2E2E2),
      false,
    ),
    // Warm paper (#F4ECD8) with dark-brown ink (#1C160F).
    ReaderColorMode.sepia => const ReaderColors._(
      ColorFilter.matrix(<double>[
        0.847, 0, 0, 0, 28, //
        0, 0.839, 0, 0, 22,
        0, 0, 0.788, 0, 15,
        0, 0, 0, 1, 0,
      ]),
      Color(0xFF2B2B2E),
      true,
    ),
  };

  Widget apply(Widget child) => filter == null
      ? child
      : ColorFiltered(colorFilter: filter!, child: child);
}
