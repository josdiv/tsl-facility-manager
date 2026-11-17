import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/di/injection.dart';
import '../core/router/app_router.dart';
import '../core/router/app_routes.dart';
import '../core/theme/app_theme.dart';
import '../features/attendance/domain/attendance.dart';
import '../features/attendance/presentation/attendance_cubit.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/session_cubit.dart';
import '../features/messaging/domain/chat.dart';
import '../features/parts/presentation/requisitions_cubit.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/work_orders/domain/work_order_repository.dart';
import '../features/work_orders/presentation/bloc/work_orders_bloc.dart';

class TslFacilityManagerApp extends StatefulWidget {
  const TslFacilityManagerApp({this.initialLocation, super.key});

  final String? initialLocation;

  @override
  State<TslFacilityManagerApp> createState() => _TslFacilityManagerAppState();
}

class _TslFacilityManagerAppState extends State<TslFacilityManagerApp> {
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation ?? AppRoutes.clientLogin,
    session: sl<SessionCubit>(),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: sl<AuthRepository>()),
        RepositoryProvider<WorkOrderRepository>.value(
          value: sl<WorkOrderRepository>(),
        ),
        RepositoryProvider<ChatRepository>.value(value: sl<ChatRepository>()),
        RepositoryProvider<AttendanceRepository>.value(
          value: sl<AttendanceRepository>(),
        ),
        RepositoryProvider<LocationService>.value(value: sl<LocationService>()),
      ],
      child: _providers(),
    );
  }

  Widget _providers() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<SessionCubit>()),
        BlocProvider(
          create: (_) => sl<WorkOrdersBloc>()..add(const WorkOrdersRequested()),
        ),
        BlocProvider(create: (_) => sl<AttendanceCubit>()),
        BlocProvider(create: (_) => sl<ProfileCubit>()),
        BlocProvider(create: (_) => sl<RequisitionsCubit>()),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        // Tapping outside a field closes the keyboard. Multi-line fields have
        // no other way to dismiss it on iOS.
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
      ),
    );
  }
}
