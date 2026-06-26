import 'component_dto.dart';

/// Wire shape of an Environment aggregate as published by the backend
/// Environment Catalog (`EnvironmentDto`), with its owned Components. A faithful
/// mirror of the server contract; the anti-corruption layer translates it into
/// a UI-facing view model.
class EnvironmentDto {
  final int id;
  final String? name;
  final String? memo;
  final List<ComponentDto> components;

  const EnvironmentDto({
    required this.id,
    this.name,
    this.memo,
    this.components = const [],
  });

  factory EnvironmentDto.fromJson(Map<String, dynamic> json) {
    return EnvironmentDto(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String?,
      memo: json['memo'] as String?,
      components:
          (json['components'] as List?)
              ?.map((e) => ComponentDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
