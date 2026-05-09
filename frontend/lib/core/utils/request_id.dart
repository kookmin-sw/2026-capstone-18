import 'dart:math';

String newRequestId() {
  final random = Random.secure();
  final millis = DateTime.now().millisecondsSinceEpoch;
  final suffix = List<int>.generate(
    8,
    (_) => random.nextInt(16),
  ).map((value) => value.toRadixString(16)).join();

  return 'req-$millis-$suffix';
}
