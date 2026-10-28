class FeedCategory {
  const FeedCategory({required this.id, required this.name});

  final String id;
  final String name;

  FeedCategory copyWith({String? name}) =>
      FeedCategory(id: id, name: name ?? this.name);
}
