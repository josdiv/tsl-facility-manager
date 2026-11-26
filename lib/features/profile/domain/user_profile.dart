import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../core/session/app_role.dart';

/// A facility someone can be linked to.
class Facility extends Equatable {
  const Facility(
    this.id,
    this.name, {
    this.latitude,
    this.longitude,
    this.radiusM = 100,
  });

  final String id;
  final String name;

  /// Where the facility is, once the dashboard has set it. Clients can only
  /// report from within [radiusM] metres of it.
  final double? latitude;
  final double? longitude;
  final double radiusM;

  bool get hasPosition => latitude != null && longitude != null;

  /// Metres from [latitude], [longitude] on the Earth's surface. Only call
  /// when [hasPosition].
  double distanceFrom(double latitude, double longitude) {
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(latitude - this.latitude!);
    final dLng = rad(longitude - this.longitude!);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(this.latitude!)) *
            math.cos(rad(latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371000 * math.asin(math.sqrt(h));
  }

  @override
  List<Object?> get props => [id, name, latitude, longitude, radiusM];
}

/// Facilities a client can choose from in sample mode.
const sampleFacilityOptions = [
  Facility(
    'marina',
    'Marina Towers, Lagos',
    latitude: 6.4515,
    longitude: 3.3886,
  ),
  Facility('cedar', 'Cedar Court, Abuja', latitude: 9.0812, longitude: 7.4951),
  Facility(
    'harbour',
    'Harbour Point, Lekki',
    latitude: 6.4474,
    longitude: 3.4723,
  ),
];

/// Names of [sampleFacilityOptions], for pickers that only need the label.
final sampleFacilities = [for (final f in sampleFacilityOptions) f.name];

/// The signed-in person. Matches `users/{uid}` in docs/firestore-schema.md.
class UserProfile extends Equatable {
  const UserProfile({
    required this.name,
    required this.phone,
    required this.email,
    required this.facility,
    this.uid = '',
    this.role = AppRole.client,
    this.locationId,
    this.companyId,
    this.companyName,
    this.designation,
  });

  final String uid;
  final AppRole role;
  final String name;
  final String phone;
  final String email;

  /// The facility's name. [locationId] is its document ID.
  final String facility;
  final String? locationId;
  final String? companyId;
  final String? companyName;
  final String? designation;

  /// First name, for greetings.
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// Up to two initials, for the avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  UserProfile copyWith({
    String? name,
    String? phone,
    String? facility,
    String? locationId,
  }) => UserProfile(
    uid: uid,
    role: role,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email,
    facility: facility ?? this.facility,
    locationId: locationId ?? this.locationId,
    companyId: companyId,
    companyName: companyName,
    designation: designation,
  );

  @override
  List<Object?> get props => [
    uid,
    role,
    name,
    phone,
    email,
    facility,
    locationId,
    companyId,
    companyName,
    designation,
  ];
}

/// Clients pick their own facility; the admin assigns staff and supervisors.
bool canChooseFacility(AppRole role) => role == AppRole.client;

const sampleProfiles = {
  AppRole.client: UserProfile(
    uid: 'daniel',
    role: AppRole.client,
    name: 'Daniel Clarke',
    phone: '+234 803 555 0142',
    email: 'daniel@example.com',
    facility: 'Marina Towers, Lagos',
    locationId: 'marina',
    companyId: 'acme',
    companyName: 'Acme Corp Nigeria',
  ),
  AppRole.staff: UserProfile(
    uid: 'emeka',
    role: AppRole.staff,
    name: 'Emeka Okafor',
    phone: '+234 806 555 0187',
    email: 'emeka@thickservices.com',
    facility: 'Marina Towers, Lagos',
    locationId: 'marina',
    designation: 'HVAC technician',
  ),
  AppRole.supervisor: UserProfile(
    uid: 'sarah',
    role: AppRole.supervisor,
    name: 'Sarah James',
    phone: '+234 809 555 0119',
    email: 'sarah@thickservices.com',
    facility: 'Marina Towers, Lagos',
    locationId: 'marina',
    designation: 'Facility supervisor',
  ),
};
