import 'package:equatable/equatable.dart';

import '../../../core/session/app_role.dart';

/// Facilities a client can choose from. Sample data until Firestore arrives.
const sampleFacilities = [
  'Marina Towers, Lagos',
  'Cedar Court, Abuja',
  'Harbour Point, Lekki',
];

class UserProfile extends Equatable {
  const UserProfile({
    required this.name,
    required this.phone,
    required this.email,
    required this.facility,
  });

  final String name;
  final String phone;
  final String email;
  final String facility;

  /// Up to two initials, for the avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  UserProfile copyWith({String? name, String? phone, String? facility}) =>
      UserProfile(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email,
        facility: facility ?? this.facility,
      );

  @override
  List<Object?> get props => [name, phone, email, facility];
}

/// Clients pick their own facility; the admin assigns staff and supervisors.
bool canChooseFacility(AppRole role) => role == AppRole.client;

const sampleProfiles = {
  AppRole.client: UserProfile(
    name: 'Daniel Clarke',
    phone: '+234 803 555 0142',
    email: 'daniel@example.com',
    facility: 'Marina Towers, Lagos',
  ),
  AppRole.staff: UserProfile(
    name: 'Emeka Okafor',
    phone: '+234 806 555 0187',
    email: 'emeka@thickservices.com',
    facility: 'Marina Towers, Lagos',
  ),
  AppRole.supervisor: UserProfile(
    name: 'Sarah James',
    phone: '+234 809 555 0119',
    email: 'sarah@thickservices.com',
    facility: 'Marina Towers, Lagos',
  ),
};
