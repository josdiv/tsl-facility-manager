import 'package:get_it/get_it.dart';

import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/auth/data/sample_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/presentation/session_cubit.dart';
import '../../features/messaging/presentation/messaging_pages.dart';
import '../../features/parts/presentation/requisitions_cubit.dart';
import '../../features/profile/presentation/profile_cubit.dart';
import '../../features/work_orders/data/in_memory_work_order_repository.dart';
import '../../features/work_orders/domain/work_order_repository.dart';
import '../../features/work_orders/presentation/bloc/work_orders_bloc.dart';

final GetIt sl = GetIt.instance;

/// Registers the app's dependencies. With [useFirebase] off, everything runs
/// on in-memory sample data and no sign-in is enforced, as the widget tests
/// and `--dart-define=SAMPLE_DATA=true` builds expect.
void configureDependencies({bool useFirebase = false}) {
  sl
    ..registerLazySingleton<AuthRepository>(
      useFirebase ? FirebaseAuthRepository.new : SampleAuthRepository.new,
    )
    ..registerLazySingleton(
      () => SessionCubit(sl(), enforced: useFirebase),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<WorkOrderRepository>(
      InMemoryWorkOrderRepository.new,
    )
    ..registerFactory(() => WorkOrdersBloc(sl()))
    ..registerFactory(AttendanceCubit.new)
    ..registerFactory(MessagesCubit.new)
    ..registerFactory(
      () => ProfileCubit(auth: useFirebase ? sl<AuthRepository>() : null),
    )
    ..registerFactory(RequisitionsCubit.new);
}
