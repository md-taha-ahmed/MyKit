import '../entities/countdown.dart';

abstract interface class CountdownRepository {
  List<Countdown> getAll();

  Future<void> saveAll(List<Countdown> countdowns);
}
