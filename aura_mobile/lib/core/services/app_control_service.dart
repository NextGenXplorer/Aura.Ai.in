import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appControlServiceProvider = Provider((ref) => AppControlService());

class AppControlService {
  static const platform = MethodChannel('com.aura.ai/app_control');

  Future<void> openApp(String appName) async {
    try {
      await platform.invokeMethod('openApp', {'appName': appName});
    } on PlatformException catch (e) {
      debugPrint("Failed to open app '$appName': ${e.message}");
      throw "Could not open $appName. ${e.message}";
    }
  }

  Future<void> closeApp(String appName) async {
    try {
      await platform.invokeMethod('closeApp', {'appName': appName});
    } on PlatformException catch (e) {
      debugPrint("Failed to close app '$appName': ${e.message}");
      // Don't throw, just log, as closing apps is restricted
    }
  }

  Future<void> openSettings(String type) async {
    try {
      await platform.invokeMethod('openSettings', {'type': type});
    } on PlatformException catch (e) {
      debugPrint("Failed to open settings '$type': ${e.message}");
      throw "Could not open settings.";
    }
  }

  Future<void> openCamera() async {
    try {
      await platform.invokeMethod('openCamera');
    } on PlatformException catch (e) {
      debugPrint("Failed to open camera: ${e.message}");
      throw "Could not open camera.";
    }
  }

  Future<void> dialContact(String nameOrNumber) async {
    try {
      await platform.invokeMethod('dialContact', {'name': nameOrNumber});
    } on PlatformException catch (e) {
      debugPrint("Failed to dial '$nameOrNumber': ${e.message}");
      throw "Could not dial $nameOrNumber.";
    }
  }

  Future<void> sendSMS(String nameOrNumber, String message) async {
    try {
      await platform.invokeMethod('sendSMS', {'name': nameOrNumber, 'message': message});
    } on PlatformException catch (e) {
      debugPrint("Failed to send SMS to '$nameOrNumber': ${e.message}");
      throw "Could not send SMS.";
    }
  }
}
