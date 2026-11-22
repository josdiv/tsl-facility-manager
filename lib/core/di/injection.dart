import 'package:get_it/get_it.dart';

import '../media/photo_service.dart';

import '../../features/attendance/data/firebase_attendance_repository.dart';
import '../../features/attendance/data/geolocator_location_service.dart';
import '../../features/attendance/data/sample_attendance.dart';
import '../../features/attendance/domain/attendance.dart';
import '../../features/attendance/presentation/attendance_cubit.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/auth/data/sample_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/presentation/session_cubit.dart';
import '../../features/messaging/data/firestore_chat_repository.dart';
import '../../features/messaging/data/in_memory_chat_repository.dart';
import '../../features/messaging/domain/chat.dart';
import '../../features/notifications/data/fcm_push_service.dart';
import '../../features/notifications/data/firestore_notification_repository.dart';
import '../../features/notifications/data/sample_notifications.dart';
import '../../features/notifications/domain/notifications.dart';
import '../../features/parts/data/firestore_parts_repository.dart';
import '../../features/parts/data/in_memory_parts_repository.dart';
import '../../features/parts/domain/requisition.dart';
import '../../features/profile/presentation/profile_cubit.dart';
import '../../features/work_orders/data/firestore_work_order_repository.dart';
import '../../features/work_orders/data/in_memory_work_order_repository.dart';
import '../../features/work_orders/domain/work_order_repository.dart';
import '../../features/work_orders/presentation/bloc/work_orders_bloc.dart';

final GetIt sl = GetIt.instance;

/// Registers the app's dependencies. With [useFirebase] off, everything runs
/// on in-memory sample data and no sign-in is enforced, as the widget tests
/// and `--dart-define=SAMPLE_DATA=true` builds expect.
void configureDependencies({bool useFirebase = false}) {
  if (useFirebase) {
    sl
      ..registerLazySingleton<PhotoService>(FirebasePhotoService.new)
      ..registerLazySingleton(
        () => FirestoreWorkOrderRepository(photos: sl(), location: sl()),
      )
      ..registerLazySingleton<WorkOrderRepository>(
        sl<FirestoreWorkOrderRepository>,
      )
      ..registerLazySingleton<ChatRepository>(
        () => FirestoreChatRepository(
          workOrderDocId: sl<FirestoreWorkOrderRepository>().docIdFor,
        ),
      )
      ..registerLazySingleton<AttendanceRepository>(
        FirebaseAttendanceRepository.new,
      )
      ..registerLazySingleton<LocationService>(
        () => const GeolocatorLocationService(),
      )
      ..registerLazySingleton<NotificationRepository>(
        FirestoreNotificationRepository.new,
      )
      ..registerLazySingleton<PushService>(FcmPushService.new)
      ..registerLazySingleton<PartsRepository>(
        () => FirestorePartsRepository(
          workOrderDocId: sl<FirestoreWorkOrderRepository>().docIdFor,
        ),
      );
  } else {
    sl
      ..registerLazySingleton<PhotoService>(SamplePhotoService.new)
      ..registerLazySingleton(InMemoryWorkOrderRepository.new)
      ..registerLazySingleton<WorkOrderRepository>(
        sl<InMemoryWorkOrderRepository>,
      )
      ..registerLazySingleton<ChatRepository>(
        () => InMemoryChatRepository(
          workOrders: sl<InMemoryWorkOrderRepository>(),
        ),
      )
      ..registerLazySingleton<AttendanceRepository>(
        InMemoryAttendanceRepository.new,
      )
      ..registerLazySingleton<LocationService>(
        () => const SampleLocationService(),
      )
      ..registerLazySingleton<NotificationRepository>(
        InMemoryNotificationRepository.new,
      )
      ..registerLazySingleton<PushService>(() => const NoPushService())
      ..registerLazySingleton<PartsRepository>(InMemoryPartsRepository.new);
  }

  sl
    ..registerLazySingleton<AuthRepository>(
      useFirebase ? FirebaseAuthRepository.new : SampleAuthRepository.new,
    )
    ..registerLazySingleton(
      () => SessionCubit(sl(), enforced: useFirebase, push: sl()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerFactory(
      () => WorkOrdersBloc(
        sl(),
        // With Firebase, follow whoever is signed in.
        scope: useFirebase ? sl<AuthRepository>().watchUser() : null,
      ),
    )
    ..registerFactory(
      () => AttendanceCubit(
        sl(),
        signedIn: useFirebase ? sl<AuthRepository>().watchUser() : null,
      ),
    )
    ..registerFactory(
      () => ProfileCubit(auth: useFirebase ? sl<AuthRepository>() : null),
    );
}
