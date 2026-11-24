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

/// The latest values of [a] and [b] combined, once both have emitted.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false, doneA = false, doneB = false;
  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  void done() {
    if (doneA && doneB) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          lastA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          done();
        },
      );
      subB = b.listen(
        (v) {
          lastB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          done();
        },
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
