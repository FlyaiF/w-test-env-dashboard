import 'env_info.dart';

class RuntimeEnvFreshInfo {
  final String? systemVersion;
  final String? subsystemVer;
  final DateTime? beginTime;

  RuntimeEnvFreshInfo({this.systemVersion, this.subsystemVer, this.beginTime});

  factory RuntimeEnvFreshInfo.fromJson(Map<String, dynamic> json) {
    return RuntimeEnvFreshInfo(
      systemVersion: _trim(json['system_version'] as String?),
      subsystemVer: _trim(json['subsystem_ver'] as String?),
      beginTime: json['begin_time'] != null
          ? DateTime.tryParse(json['begin_time'] as String)
          : null,
    );
  }
}

class RuntimeEnvDiff {
  final bool versionChanged;
  final bool updateTimeChanged;

  RuntimeEnvDiff({
    required this.versionChanged,
    required this.updateTimeChanged,
  });

  factory RuntimeEnvDiff.fromJson(Map<String, dynamic> json) {
    return RuntimeEnvDiff(
      versionChanged: json['version_changed'] == true,
      updateTimeChanged: json['update_time_changed'] == true,
    );
  }
}

class RuntimeEnvCollectionResult {
  final int eNo;
  final String? eName;
  final String status;
  final EnvInfo current;
  final RuntimeEnvFreshInfo? fresh;
  final RuntimeEnvDiff diff;
  final String? error;
  final DateTime? collectedAt;

  RuntimeEnvCollectionResult({
    required this.eNo,
    this.eName,
    required this.status,
    required this.current,
    this.fresh,
    required this.diff,
    this.error,
    this.collectedAt,
  });

  bool get isChanged => status == 'changed';
  bool get isPublishable =>
      isChanged &&
      fresh != null &&
      (fresh!.systemVersion != null || fresh!.beginTime != null);

  factory RuntimeEnvCollectionResult.fromJson(Map<String, dynamic> json) {
    return RuntimeEnvCollectionResult(
      eNo: json['e_no'] as int,
      eName: _trim(json['e_name'] as String?),
      status: json['status'] as String? ?? 'failed',
      current: EnvInfo.fromJson(json['current'] as Map<String, dynamic>),
      fresh: json['fresh'] != null
          ? RuntimeEnvFreshInfo.fromJson(json['fresh'] as Map<String, dynamic>)
          : null,
      diff: RuntimeEnvDiff.fromJson(
        json['diff'] as Map<String, dynamic>? ?? const {},
      ),
      error: _trim(json['error'] as String?),
      collectedAt: json['collected_at'] != null
          ? DateTime.tryParse(json['collected_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toPublishJson() {
    return {
      'e_no': eNo,
      if (fresh?.systemVersion != null) 'system_version': fresh!.systemVersion,
      if (fresh?.beginTime != null)
        'begin_time_text': _formatOracleDateText(fresh!.beginTime!.toLocal()),
    };
  }
}

class RuntimePublishResult {
  final int updated;
  final List<int> skipped;
  final List<EnvInfo> data;

  RuntimePublishResult({
    required this.updated,
    required this.skipped,
    required this.data,
  });

  factory RuntimePublishResult.fromJson(Map<String, dynamic> json) {
    return RuntimePublishResult(
      updated: json['updated'] as int? ?? 0,
      skipped: (json['skipped'] as List<dynamic>? ?? const [])
          .map((e) => e as int)
          .toList(),
      data: (json['data'] as List<dynamic>? ?? const [])
          .map((e) => EnvInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

String? _trim(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatOracleDateText(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
