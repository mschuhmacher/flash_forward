class UserProfile {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? phoneNumber;
  final String? country;
  final bool marketingConsent;
  final DateTime accountCreatedAt;
  final String? appVersionAtSignup;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phoneNumber,
    this.country,
    required this.marketingConsent,
    required this.accountCreatedAt,
    this.appVersionAtSignup,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String, // No null safety operator
      lastName: json['last_name'] as String, // No null safety operator
      phoneNumber: json['phone_number'] as String?,
      country: json['country'] as String?,
      marketingConsent: json['marketing_consent'] as bool? ?? false,
      accountCreatedAt: DateTime.parse(json['account_created_at'] as String),
      appVersionAtSignup: json['app_version_at_signup'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'country': country,
      'marketing_consent': marketingConsent,
      'account_created_at': accountCreatedAt.toIso8601String(),
      'app_version_at_signup': appVersionAtSignup,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get fullName {
    return '$firstName $lastName'.trim(); // Simplified since both are required
  }

  UserProfile copyWith({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? country,
    bool? marketingConsent,
  }) {
    return UserProfile(
      id: id,
      email: email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      country: country ?? this.country,
      marketingConsent: marketingConsent ?? this.marketingConsent,
      accountCreatedAt: accountCreatedAt,
      appVersionAtSignup: appVersionAtSignup,
      updatedAt: DateTime.now(),
    );
  }
}
