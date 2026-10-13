import 'package:shared_preferences/shared_preferences.dart';

final _preferences = SharedPreferencesAsync();
const _key = 'zizouit_manager_v1';

Future<String?> readData() => _preferences.getString(_key);
Future<void> writeData(String data) async {
  final previous = await readData();
  if (previous != null) {
    await _preferences.setString('${_key}_previous', previous);
  }
  await _preferences.setString(_key, data);
}
