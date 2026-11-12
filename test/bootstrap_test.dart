import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tsl_facility_manager/bootstrap.dart';
import 'package:tsl_facility_manager/features/work_orders/domain/work_order_repository.dart';

void main() {
  setUp(() => GetIt.instance.reset());

  test('starts Firebase before registering dependencies', () async {
    var registeredWhenFirebaseStarted = true;
    await bootstrap(
      firebase: () async {
        registeredWhenFirebaseStarted = GetIt.instance
            .isRegistered<WorkOrderRepository>();
      },
    );

    expect(registeredWhenFirebaseStarted, isFalse);
    expect(GetIt.instance.isRegistered<WorkOrderRepository>(), isTrue);
  });

  test('a Firebase start-up failure stops bootstrap', () async {
    await expectLater(
      bootstrap(firebase: () async => throw StateError('no Firebase')),
      throwsStateError,
    );
    expect(GetIt.instance.isRegistered<WorkOrderRepository>(), isFalse);
  });
}
