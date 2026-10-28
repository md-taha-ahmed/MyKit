import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Describes a single tool that lives on the dashboard.
///
/// Every feature exposes one [ToolDefinition]. Registering it in
/// `lib/app/tools_registry.dart` is all that's needed for the tool to show up on the
/// dashboard and for its routes to be wired into the router.
class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.rootPath,
    required this.routes,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  /// Path the dashboard navigates to when the tool card is tapped.
  final String rootPath;

  /// Top-level routes owned by this tool.
  final List<RouteBase> routes;
}
