import 'dart:async';

/// Combina più stream: emette la lista degli ultimi valori ogni volta che uno
/// stream cambia, dopo che tutti hanno emesso almeno una volta.
Stream<List<Object?>> combineLatestAll(List<Stream<Object?>> streams) {
  final values = List<Object?>.filled(streams.length, null);
  final received = List<bool>.filled(streams.length, false);
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<List<Object?>> controller;
  var done = 0;

  void emit() {
    if (received.every((r) => r)) controller.add(List.unmodifiable(values));
  }

  controller = StreamController<List<Object?>>(
    onListen: () {
      for (final (i, s) in streams.indexed) {
        subscriptions.add(
          s.listen(
            (v) {
              values[i] = v;
              received[i] = true;
              emit();
            },
            onError: controller.addError,
            onDone: () {
              if (++done == streams.length) controller.close();
            },
          ),
        );
      }
    },
    onPause: () {
      for (final s in subscriptions) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subscriptions) {
        s.resume();
      }
    },
    onCancel: () => Future.wait(subscriptions.map((s) => s.cancel())),
  );
  return controller.stream;
}

/// Versione tipizzata per due stream.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) =>
    combineLatestAll([a, b]).map((v) => combine(v[0] as A, v[1] as B));
