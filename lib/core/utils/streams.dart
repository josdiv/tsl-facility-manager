import 'dart:async';

extension SwitchMap<T> on Stream<T> {
  /// Maps each event to a stream and follows only the latest one, cancelling
  /// the previous. Unlike [asyncExpand], it doesn't wait for the previous
  /// stream to finish, which Firestore listeners never do.
  ///
  /// The result ends once this stream and the latest inner stream have both
  /// ended.
  Stream<R> switchMap<R>(Stream<R> Function(T event) convert) {
    late final StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;
    var outerDone = false;
    var innerDone = true;

    void closeIfFinished() {
      if (outerDone && innerDone) unawaited(controller.close());
    }

    controller = StreamController<R>(
      onListen: () {
        outer = listen(
          (event) {
            unawaited(inner?.cancel());
            innerDone = false;
            inner = convert(event).listen(
              controller.add,
              onError: controller.addError,
              onDone: () {
                innerDone = true;
                closeIfFinished();
              },
            );
          },
          onError: controller.addError,
          onDone: () {
            outerDone = true;
            closeIfFinished();
          },
        );
      },
      onPause: () {
        outer?.pause();
        inner?.pause();
      },
      onResume: () {
        outer?.resume();
        inner?.resume();
      },
      onCancel: () async {
        await inner?.cancel();
        await outer?.cancel();
      },
    );
    return controller.stream;
  }
}
