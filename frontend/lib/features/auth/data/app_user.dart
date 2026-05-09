class AppUser {
  final String id;
  final String? email;
  final String? name;
  final String accountType;
  final Map<String, dynamic> consent;
  final Map<String, dynamic> settings;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.accountType,
    required this.consent,
    required this.settings,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final isAnonymous =
        json['supabase_user_id'] == null && json['anon_id'] != null;
    return AppUser(
      id: '${json['id'] ?? json['user_id'] ?? ''}',
      email: json['email'] as String?,
      name: (json['name'] ?? json['display_name']) as String?,
      accountType:
          '${json['account_type'] ?? json['type'] ?? (isAnonymous ? 'anonymous' : json['role'] ?? 'user')}',
      consent: {
        ..._map(json['consent']),
        if (json.containsKey('consent_raw_biosignals'))
          'consent_raw_biosignals': json['consent_raw_biosignals'],
        if (json.containsKey('consent_revoked_at'))
          'consent_revoked_at': json['consent_revoked_at'],
      },
      settings: _map(json['settings']),
    );
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? accountType,
    Map<String, dynamic>? consent,
    Map<String, dynamic>? settings,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      consent: consent ?? this.consent,
      settings: settings ?? this.settings,
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return <String, dynamic>{};
  }
}
