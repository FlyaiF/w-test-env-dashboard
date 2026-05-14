class Environment {
  final int eNo;
  final String? name;
  final String? url;
  final String? seeUrl;
  final String? version;
  final String? ywdb;
  final String? zjdb;
  final String? dbType;
  final String? webLogPath;
  final String? memo;
  final DateTime? updateTime;
  final String? serverHost;
  final String? webserverAddrRaw; // original E_WEBSERVERADDR for round-trip
  final DateTime? lastSyncedAt;

  Environment({
    required this.eNo,
    this.name,
    this.url,
    this.seeUrl,
    this.version,
    this.ywdb,
    this.zjdb,
    this.dbType,
    this.webLogPath,
    this.memo,
    this.updateTime,
    this.serverHost,
    this.webserverAddrRaw,
    this.lastSyncedAt,
  });

  factory Environment.fromJson(Map<String, dynamic> json) {
    return Environment(
      eNo: json['eNo'] as int,
      name: json['name'] as String?,
      url: json['url'] as String?,
      seeUrl: json['seeUrl'] as String?,
      version: json['version'] as String?,
      ywdb: json['ywdb'] as String?,
      zjdb: json['zjdb'] as String?,
      dbType: json['dbType'] as String?,
      webLogPath: json['webLogPath'] as String?,
      memo: json['memo'] as String?,
      updateTime: json['updateTime'] != null
          ? DateTime.tryParse(json['updateTime'] as String)
          : null,
      serverHost: json['serverHost'] as String?,
      webserverAddrRaw: json['webserverAddrRaw'] as String?,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eNo': eNo,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (seeUrl != null) 'seeUrl': seeUrl,
      if (version != null) 'version': version,
      if (ywdb != null) 'ywdb': ywdb,
      if (zjdb != null) 'zjdb': zjdb,
      if (dbType != null) 'dbType': dbType,
      if (webLogPath != null) 'webLogPath': webLogPath,
      if (memo != null) 'memo': memo,
      if (updateTime != null) 'updateTime': updateTime!.toIso8601String(),
      if (serverHost != null) 'serverHost': serverHost,
      if (webserverAddrRaw != null) 'webserverAddrRaw': webserverAddrRaw,
      if (lastSyncedAt != null)
        'lastSyncedAt': lastSyncedAt!.toIso8601String(),
    };
  }

  Environment copyWith({
    int? eNo,
    String? name,
    String? url,
    String? seeUrl,
    String? version,
    String? ywdb,
    String? zjdb,
    String? dbType,
    String? webLogPath,
    String? memo,
    DateTime? updateTime,
    String? serverHost,
    String? webserverAddrRaw,
    DateTime? lastSyncedAt,
  }) {
    return Environment(
      eNo: eNo ?? this.eNo,
      name: name ?? this.name,
      url: url ?? this.url,
      seeUrl: seeUrl ?? this.seeUrl,
      version: version ?? this.version,
      ywdb: ywdb ?? this.ywdb,
      zjdb: zjdb ?? this.zjdb,
      dbType: dbType ?? this.dbType,
      webLogPath: webLogPath ?? this.webLogPath,
      memo: memo ?? this.memo,
      updateTime: updateTime ?? this.updateTime,
      serverHost: serverHost ?? this.serverHost,
      webserverAddrRaw: webserverAddrRaw ?? this.webserverAddrRaw,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
