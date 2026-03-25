import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final smartAppActionsProvider = Provider((ref) => SmartAppActionsService());

/// Smart App Actions Service
///
/// Provides deep link workflows to interact with popular apps
/// (WhatsApp, Spotify, UPI, Uber/Ola, Swiggy/Zomato, Instagram, etc.)
/// Uses the existing `com.aura.ai/app_control` MethodChannel.
class SmartAppActionsService {
  static const _channel = MethodChannel('com.aura.ai/app_control');

  /// Send a WhatsApp message to a contact.
  Future<void> sendWhatsApp(String contact, String message) async {
    try {
      await _channel.invokeMethod('sendWhatsApp', {
        'contact': contact,
        'message': message,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: sendWhatsApp failed: ${e.message}');
      rethrow;
    }
  }

  /// Search for a query on a specific app (Amazon, Flipkart, Google, etc.)
  Future<void> searchOnApp(String appName, String query) async {
    try {
      await _channel.invokeMethod('searchOnApp', {
        'appName': appName,
        'query': query,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: searchOnApp failed: ${e.message}');
      rethrow;
    }
  }

  /// Initiate a UPI payment (works with GPay, PhonePe, Paytm, etc.)
  Future<void> makeUpiPayment({
    String? upiId,
    String? amount,
    String? note,
  }) async {
    try {
      await _channel.invokeMethod('makeUpiPayment', {
        'upiId': upiId,
        'amount': amount,
        'note': note,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: makeUpiPayment failed: ${e.message}');
      rethrow;
    }
  }

  /// Play a song/artist/playlist on Spotify.
  Future<void> playOnSpotify(String query) async {
    try {
      await _channel.invokeMethod('playOnSpotify', {
        'query': query,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: playOnSpotify failed: ${e.message}');
      rethrow;
    }
  }

  /// Book a ride to a destination (Uber, Ola, or auto-detect).
  Future<void> bookRide(String destination, {String? app}) async {
    try {
      await _channel.invokeMethod('bookRide', {
        'destination': destination,
        'app': app,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: bookRide failed: ${e.message}');
      rethrow;
    }
  }

  /// Order food from Swiggy/Zomato.
  Future<void> orderFood({String? restaurant, String? app}) async {
    try {
      await _channel.invokeMethod('orderFood', {
        'restaurant': restaurant,
        'app': app,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: orderFood failed: ${e.message}');
      rethrow;
    }
  }

  /// Share text content to a specific app or general share sheet.
  Future<void> shareText(String text, {String? app}) async {
    try {
      await _channel.invokeMethod('shareText', {
        'text': text,
        'app': app,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: shareText failed: ${e.message}');
      rethrow;
    }
  }

  /// Open a user profile on a social media platform.
  Future<void> openProfile(String platform, String username) async {
    try {
      await _channel.invokeMethod('openProfile', {
        'platform': platform,
        'username': username,
      });
    } on PlatformException catch (e) {
      debugPrint('SmartAppActions: openProfile failed: ${e.message}');
      rethrow;
    }
  }
}
