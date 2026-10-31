/// One saved login.
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.passwordChangedAt,
  });

  final String id;
  final String title;
  final String username;
  final String password;

  /// Website or app address (may be empty).
  final String url;
  final String notes;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? passwordChangedAt;

  /// "github.com" from the URL, for display and matching.
  String get host {
    final raw = url.trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    final host = uri?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    bool? favorite,
    DateTime? updatedAt,
  }) {
    final passwordChanged = password != null && password != this.password;
    final now = updatedAt ?? DateTime.now();
    return VaultEntry(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt,
      updatedAt: now,
      passwordChangedAt: passwordChanged ? now : passwordChangedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'favorite': favorite,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'passwordChangedAt': passwordChangedAt?.toIso8601String(),
  };

  static VaultEntry fromJson(Map<String, dynamic> j) => VaultEntry(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    username: j['username'] as String? ?? '',
    password: j['password'] as String? ?? '',
    url: j['url'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    favorite: j['favorite'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    passwordChangedAt: DateTime.tryParse(
      j['passwordChangedAt'] as String? ?? '',
    ),
  );
}
