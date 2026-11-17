import 'dart:async';

extension SwitchMap<T> on Stream<T> {
  /// Maps each event to a stream and follows only the latest one, cancelling
  /// the previous. Unlike [asyncExpand], it doesn't wait for the previous
  /// stream to finish, which Firestore listeners never do.
  Stream<R> switchMap<R>(Stream<R> Function(T event) convert) {
    late final StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;

    controller = StreamController<R>(
      onListen: () {
        outer = listen(
          (event) {
            unawaited(inner?.cancel());
            inner = convert(event)
                .listen(controller.add, onError: controller.addError);
          },
          onError: controller.addError,
          onDone: () async {
            await inner?.cancel();
            await controller.close();
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
