import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display settings (device par save hoti hain).
/// `showRoomCategory` ek ValueNotifier hai — Profile me toggle karte hi
/// Dashboard / Bookings / Notifications turant refresh ho jaate hain.
class DisplayPrefs {
  DisplayPrefs._();
  static final DisplayPrefs instance = DisplayPrefs._();

  static const _kShowRoomCategory = 'show_room_category';

  final ValueNotifier<bool> showRoomCategory = ValueNotifier<bool>(false);

  Future<void>? _loading;   // ek hi baar load ho, chahe kitni screens bulayein
  bool _userChanged = false; // user ne toggle kiya to purana load value overwrite na kare

  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getBool(_kShowRoomCategory);
      debugPrint('[DisplayPrefs] loaded show_room_category = $saved');
      if (!_userChanged && saved != null) showRoomCategory.value = saved;
    } catch (e) {
      debugPrint('[DisplayPrefs] load failed: $e');
    }
  }

  Future<void> setShowRoomCategory(bool v) async {
    _userChanged = true;
    showRoomCategory.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      final ok = await p.setBool(_kShowRoomCategory, v);
      debugPrint('[DisplayPrefs] saved show_room_category = $v (ok: $ok)');
    } catch (e) {
      debugPrint('[DisplayPrefs] save failed: $e');
    }
  }
}