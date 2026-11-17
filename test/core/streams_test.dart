import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/core/utils/streams.dart';

void main() {
  test(
    'switchMap follows the latest inner stream, even an endless one',
    () async {
      final outer = StreamController<String?>();
      final profiles = StreamController<String>.broadcast();
      final seen = <String?>[];
      final sub = outer.stream
          .switchMap(
            (user) => user == null
                ? Stream<String?>.value(null)
                : profiles.stream.map((p) => '$user:$p'),
          )
          .listen(seen.add);

      outer.add('emeka');
      await pumpEventQueue();
      profiles.add('v1');
      await pumpEventQueue();

      // Signing out must get through although the profile stream never ends.
      outer.add(null);
      await pumpEventQueue();
      profiles.add('v2');
      await pumpEventQueue();

      expect(seen, ['emeka:v1', null]);
      await sub.cancel();
      expect(profiles.hasListener, isFalse);
    },
  );
}
