import 'package:equatable/equatable.dart';

import '../../profile/domain/user_profile.dart';
import 'work_order.dart';

/// Someone on a facility's team, for assigning work.
class TeamMember extends Equatable {
  const TeamMember({
    required this.uid,
    required this.name,
    this.designation,
    this.onShift = false,
  });

  final String uid;
  final String name;
  final String? designation;
  final bool onShift;

  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
      .join();

  @override
  List<Object?> get props => [uid, name, designation, onShift];
}

/// An area inside a facility.
class Zone extends Equatable {
  const Zone(this.id, this.name);

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

/// A piece of equipment at a facility, which a client can report a fault on.
class Asset extends Equatable {
  const Asset(this.id, this.name, {this.zone});

  final String id;
  final String name;

  /// Where it is, when the dashboard has placed it in a zone.
  final Zone? zone;

  @override
  List<Object?> get props => [id, name, zone];
}

/// What a client fills in to report an issue.
class IssueDraft extends Equatable {
  const IssueDraft({
    required this.title,
    required this.description,
    required this.location,
    this.zone,
    this.asset,
    this.assignee,
    this.media = const [],
  });

  final String title;
  final String description;
  final Facility location;

  /// Null at a facility with no zones set up yet.
  final Zone? zone;

  /// The equipment at fault, if the client picked one.
  final Asset? asset;

  /// The technician a supervisor assigns while raising the work order.
  final TeamMember? assignee;
  final List<String> media;

  @override
  List<Object?> get props => [
    title,
    description,
    location,
    zone,
    asset,
    assignee,
    media,
  ];
}

/// Why a work order action failed, in words the app can show.
class WorkOrderFailure implements Exception {
  const WorkOrderFailure(this.message, {this.code});

  final String message;

  /// `monthly-limit` when the client's company has used its requests for the
  /// month, so the app can show the dedicated screen.
  final String? code;

  @override
  String toString() => message;
}

abstract interface class WorkOrderRepository {
  /// The orders [user] may see, kept up to date. Null means every order,
  /// which only the sample data allows.
  Stream<List<WorkOrder>> watch(UserProfile? user);

  /// The timeline of one order, oldest first.
  Stream<List<WorkOrderEvent>> watchHistory(String id);

  /// Saves a lifecycle change. [before] is the order as it was and [after]
  /// is the result of a [WorkOrder] transition such as `start` or `submit`.
  Future<void> update(WorkOrder before, WorkOrder after);

  /// Creates a client request and returns its reference, such as `WO-1049`.
  /// A client reports an issue, or a supervisor raises a client work order
  /// at their facility ([reporter] is either).
  Future<String> report(IssueDraft draft, UserProfile reporter);

  /// The zones at a facility, by name.
  Future<List<Zone>> zones(String locationId);

  /// The active equipment at a facility, with the zone each is in.
  Future<List<Asset>> assets(String locationId);

  /// Staff at a facility, by name.
  Stream<List<TeamMember>> watchTeam(String locationId);
}
