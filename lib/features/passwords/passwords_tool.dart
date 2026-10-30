import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'passwords_routes.dart';
import 'presentation/providers/vault_providers.dart';

final passwordsTool = ToolDefinition(
  id: 'passwords',
  name: 'Passwords',
  description: 'Encrypted password vault',
  icon: Icons.key,
  color: passwordsAccent,
  rootPath: PasswordsRoutes.home,
  routes: PasswordsRoutes.routes,
  status: (ref) {
    final vault = ref.watch(vaultProvider);
    return switch (vault.status) {
      VaultStatus.noVault => null,
      VaultStatus.locked => 'Locked',
      VaultStatus.unlocked =>
        '${vault.entries.length} ${vault.entries.length == 1 ? 'password' : 'passwords'}',
    };
  },
);
