import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/countdown.dart';
import '../../domain/entities/countdown_theme.dart';
import 'countdown_ring.dart';

/// Shows preset themes rendered with the current countdown.
Future<CountdownTheme?> showThemePickerSheet(
  BuildContext context, {
  required Countdown countdown,
}) {
  return showModalBottomSheet<CountdownTheme>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                tr('Select theme'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .78,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final theme in CountdownTheme.presets)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, theme),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        CountdownRing(
                          size: 68,
                          countdown: countdown.copyWith(
                            ringColor: theme.ringColor,
                            backgroundColor: theme.backgroundColor,
                            trackColor: theme.trackColor,
                            textColor: theme.textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          theme.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
