import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/core/media/photo_service.dart';

void main() {
  test('photos are told apart by where they live', () {
    const web =
        'https://thickservices.com/TSLfacilitymanager/tsl/uploads/a.jpg';
    const stored = 'locations/site/workOrders/wo/work/1.jpg';
    const local = '/data/user/0/app/cache/1.jpg';
    expect(isWebPhoto(web), isTrue);
    expect(isStoredPhoto(web), isFalse);
    expect(isStoredPhoto(stored), isTrue);
    expect(isWebPhoto(stored), isFalse);
    expect(isLocalPhoto(local), isTrue);
    expect(isStoredPhoto(local), isFalse);
  });
}
