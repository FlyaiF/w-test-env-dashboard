/// Replaces a Component's Resource Inventory links in one transaction.
class ComponentLinksInput {
  final int? serverId;
  final List<int> databaseIds;

  const ComponentLinksInput({this.serverId, this.databaseIds = const []});

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'databaseIds': databaseIds,
  };
}
