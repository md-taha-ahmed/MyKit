import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'data/knowledge_catalog.dart';
import 'domain/knowledge_models.dart';
import 'knowledge_routes.dart';
import 'presentation/providers/knowledge_providers.dart';

final knowledgeTool = ToolDefinition(
  id: 'knowledge',
  name: 'علم وتاريخ',
  description: 'درس يومي في السيرة والتاريخ والفقه والعقيدة من الكتب الأصلية',
  icon: Icons.auto_stories_outlined,
  color: knowledgeAccent,
  rootPath: KnowledgeRoutes.home,
  routes: KnowledgeRoutes.routes,
  status: (ref) {
    final today = dayKey(DateTime.now());
    final done = ref.watch(lessonHistoryProvider).any((l) => l.day == today);
    final id = ref
        .watch(knowledgeSettingsProvider)
        .schedule[DateTime.now().weekday];
    final topic = KnowledgeCatalog.byId(id ?? '')?.topic;
    if (done) return 'درس اليوم جاهز${topic != null ? ': $topic' : ''}';
    return topic != null ? 'اليوم: $topic' : 'درس اليوم';
  },
);
