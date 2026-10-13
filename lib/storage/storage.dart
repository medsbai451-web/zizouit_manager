import 'package:shared_preferences/shared_preferences.dart';

final _preferences = SharedPreferencesAsync();
const _key = 'zizouit_manager_v1';

String _scopedKey(String? scope) => scope == null ? _key : '$_key:$scope';
Future<String?> readData({String? scope}) =>
    _preferences.getString(_scopedKey(scope));
Future<void> writeData(String data, {String? scope}) async {
  final key = _scopedKey(scope);
  final previous = await readData(scope: scope);
  if (previous != null) {
    await _preferences.setString('${key}_previous', previous);
  }
  await _preferences.setString(key, data);
}

Future<void> removeData(String scope) async {
  final key = _scopedKey(scope);
  await _preferences.remove(key);
  await _preferences.remove('${key}_previous');
}
