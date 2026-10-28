import '../../domain/entities/countdown.dart';
import '../../domain/repositories/countdown_repository.dart';
import '../datasources/countdown_local_data_source.dart';
import '../models/countdown_model.dart';
import '../services/countdown_home_widget_service.dart';

class CountdownRepositoryImpl implements CountdownRepository {
  CountdownRepositoryImpl(this._local, this._homeWidget);

  final CountdownLocalDataSource _local;
  final CountdownHomeWidgetService _homeWidget;

  @override
  List<Countdown> getAll() =>
      _local.readAll().map(CountdownModel.fromJson).toList();

  @override
  Future<void> saveAll(List<Countdown> countdowns) async {
    final json = countdowns.map(CountdownModel.toJson).toList();
    await _local.writeAll(json);
    // Home-screen widgets read their own copy of the data.
    await _homeWidget.sync(json);
  }
}
