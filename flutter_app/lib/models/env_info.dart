class EnvInfo {
  final int eNo;
  final String? eName;
  final String? eYwdb;
  final String? eZjdb;
  final String? eUrl;
  final String? eVersion;
  final DateTime? eUpdatetime;
  final String? eSeeurl;
  final String? eWebserveraddr;
  final String? eWeblogpath;
  final String? eMemo;
  final String? eDbtype;

  EnvInfo({
    required this.eNo,
    this.eName,
    this.eYwdb,
    this.eZjdb,
    this.eUrl,
    this.eVersion,
    this.eUpdatetime,
    this.eSeeurl,
    this.eWebserveraddr,
    this.eWeblogpath,
    this.eMemo,
    this.eDbtype,
  });

  factory EnvInfo.fromJson(Map<String, dynamic> json) {
    return EnvInfo(
      eNo: json['e_no'] as int,
      eName: json['e_name'] as String?,
      eYwdb: json['e_ywdb'] as String?,
      eZjdb: json['e_zjdb'] as String?,
      eUrl: json['e_url'] as String?,
      eVersion: json['e_version'] as String?,
      eUpdatetime: json['e_updatetime'] != null
          ? DateTime.tryParse(json['e_updatetime'] as String)
          : null,
      eSeeurl: json['e_seeurl'] as String?,
      eWebserveraddr: json['e_webserveraddr'] as String?,
      eWeblogpath: json['e_weblogpath'] as String?,
      eMemo: json['e_memo'] as String?,
      eDbtype: json['e_dbtype'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'e_no': eNo,
      if (eName != null) 'e_name': eName,
      if (eYwdb != null) 'e_ywdb': eYwdb,
      if (eZjdb != null) 'e_zjdb': eZjdb,
      if (eUrl != null) 'e_url': eUrl,
      if (eVersion != null) 'e_version': eVersion,
      if (eSeeurl != null) 'e_seeurl': eSeeurl,
      if (eWebserveraddr != null) 'e_webserveraddr': eWebserveraddr,
      if (eWeblogpath != null) 'e_weblogpath': eWeblogpath,
      if (eMemo != null) 'e_memo': eMemo,
      if (eDbtype != null) 'e_dbtype': eDbtype,
    };
  }

  EnvInfo copyWith({
    int? eNo,
    String? eName,
    String? eYwdb,
    String? eZjdb,
    String? eUrl,
    String? eVersion,
    DateTime? eUpdatetime,
    String? eSeeurl,
    String? eWebserveraddr,
    String? eWeblogpath,
    String? eMemo,
    String? eDbtype,
  }) {
    return EnvInfo(
      eNo: eNo ?? this.eNo,
      eName: eName ?? this.eName,
      eYwdb: eYwdb ?? this.eYwdb,
      eZjdb: eZjdb ?? this.eZjdb,
      eUrl: eUrl ?? this.eUrl,
      eVersion: eVersion ?? this.eVersion,
      eUpdatetime: eUpdatetime ?? this.eUpdatetime,
      eSeeurl: eSeeurl ?? this.eSeeurl,
      eWebserveraddr: eWebserveraddr ?? this.eWebserveraddr,
      eWeblogpath: eWeblogpath ?? this.eWeblogpath,
      eMemo: eMemo ?? this.eMemo,
      eDbtype: eDbtype ?? this.eDbtype,
    );
  }
}
