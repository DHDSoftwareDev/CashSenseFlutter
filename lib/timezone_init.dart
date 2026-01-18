import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class TimezoneInit {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    final String localTz = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));
    _initialized = true;
  }

  static String localTimeZoneName() {
    return tz.local.name; // e.g. "America/New_York"
  }
}
