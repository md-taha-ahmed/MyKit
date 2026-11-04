import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/tools/tool_switch.dart';
import '../../../../core/tools/tools_provider.dart';
import '../../../backup/backup_routes.dart';
import '../../../setup/setup_routes.dart';
import '../widgets/tool_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = ref.watch(disabledToolsProvider);
    final tools = ref
        .watch(toolsProvider)
        .where((t) => !off.contains(t.id))
        .toList();
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('MyKit'),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEEE, d MMMM').format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Backup'),
                      icon: const Icon(Icons.cloud_outlined),
                      onPressed: () => context.push(BackupRoutes.home),
                    ),
                    IconButton(
                      tooltip: tr('Settings'),
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => context.push(SetupRoutes.settings),
                    ),
                  ],
                ),
              ),
            ),
            if (tools.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(32),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    tr('All sections are off. Turn them on in Settings.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                ),
                delegate: SliverChildListDelegate([
                  for (final tool in tools)
                    ToolCard(
                      tool: tool,
                      onTap: () => context.push(tool.rootPath),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
