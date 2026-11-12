import 'package:get_it/get_it.dart';

import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/messaging/presentation/messaging_pages.dart';
import '../../features/profile/presentation/profile_cubit.dart';
import '../../features/work_orders/data/in_memory_work_order_repository.dart';
import '../../features/work_orders/domain/work_order_repository.dart';
import '../../features/work_orders/presentation/bloc/work_orders_bloc.dart';

final GetIt sl = GetIt.instance;

void configureDependencies() {
  sl
    ..registerLazySingleton<WorkOrderRepository>(
      InMemoryWorkOrderRepository.new,
    )
    ..registerFactory(() => WorkOrdersBloc(sl()))
    ..registerFactory(AttendanceCubit.new)
    ..registerFactory(MessagesCubit.new)
    ..registerFactory(ProfileCubit.new);
}
