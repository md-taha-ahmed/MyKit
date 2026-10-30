class FeedCategory {
  const FeedCategory({required this.id, required this.name, this.parentId});

  final String id;
  final String name;

  /// The folder this one sits in (null = top level).
  final String? parentId;

  FeedCategory copyWith({String? name, String? Function()? parentId}) =>
      FeedCategory(
        id: id,
        name: name ?? this.name,
        parentId: parentId != null ? parentId() : this.parentId,
      );
}
