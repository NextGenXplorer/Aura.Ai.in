import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:permission_handler/permission_handler.dart';

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

  Future<List<Contact>> resolveContacts(String name) async {
    if (await Permission.contacts.request().isGranted) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final query = name.toLowerCase().trim();

      if (query.isEmpty) return [];

      // 1. Exact match (highest priority)
      final exactMatches = contacts.where((c) {
        final cName = c.displayName.toLowerCase();
        return cName == query || cName.split(' ').any((part) => part == query);
      }).toList();
      if (exactMatches.isNotEmpty) return exactMatches;

      // 2. Contains match
      final containsMatches = contacts.where((c) {
        final cName = c.displayName.toLowerCase();
        return cName.contains(query) || query.contains(cName);
      }).toList();
      if (containsMatches.isNotEmpty) return containsMatches;

      // 3. Fuzzy match — handles speech recognition errors like
      // "mitun" vs "mithun", "nikki" vs "niki", "ghani" vs "gani"
      final fuzzyMatches = <_ScoredContact>[];
      for (final contact in contacts) {
        final cName = contact.displayName.toLowerCase();
        final parts = cName.split(' ');

        // Check each name part for fuzzy similarity
        for (final part in parts) {
          final distance = _levenshteinDistance(query, part);
          final maxLen = query.length > part.length ? query.length : part.length;

          // Allow up to 2 character differences for short names, 3 for longer ones
          final threshold = maxLen <= 4 ? 1 : (maxLen <= 6 ? 2 : 3);

          if (distance <= threshold) {
            fuzzyMatches.add(_ScoredContact(contact, distance));
            break; // Don't add same contact twice
          }
        }

        // Also check phonetic similarity (first 3-4 chars match)
        if (fuzzyMatches.every((m) => m.contact != contact)) {
          for (final part in parts) {
            if (part.length >= 3 && query.length >= 3) {
              // First 3 chars match — likely the same name
              if (part.substring(0, 3) == query.substring(0, 3)) {
                fuzzyMatches.add(_ScoredContact(contact, 2));
                break;
              }
            }
          }
        }
      }

      // Sort by similarity (lower distance = better match)
      fuzzyMatches.sort((a, b) => a.distance.compareTo(b.distance));
      return fuzzyMatches.take(5).map((m) => m.contact).toList();
    }
    return [];
  }

  /// Levenshtein distance — counts minimum edits to transform one string into another
  int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> prev = List.generate(t.length + 1, (i) => i);
    List<int> curr = List.filled(t.length + 1, 0);

    for (int i = 1; i <= s.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= t.length; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,      // insertion
          prev[j] + 1,          // deletion
          prev[j - 1] + cost,   // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[t.length];
  }

  Future<void> dialContact(String nameOrNumber) async {
    try {
      // 1. Check if input is a pure number (or resolved from Orchestrator)
      final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      // 2. It's a number (or look-alike), try to call directly if permission exists
      if (RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3) {
         if (await Permission.phone.request().isGranted) {
            try {
               await platform.invokeMethod('callPhoneDirect', {'number': cleanNumber});
               return;
            } catch (e) {
               debugPrint("Direct call failed for number, falling back to dialer: $e");
            }
         }
         // Fallback or permission denied
         await _launchCall(cleanNumber);
         return;
      }

      // 2. It's a name, try to find in contacts
      if (await Permission.contacts.request().isGranted) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        
        // Fuzzy search
        final query = nameOrNumber.toLowerCase();
        final match = contacts.where((c) => c.displayName.toLowerCase().contains(query)).firstOrNull;

        if (match != null && match.phones.isNotEmpty) {
          final number = match.phones.first.number;
          debugPrint("Found contact: ${match.displayName} -> $number");
          
          // Try Direct Call first
          if (await Permission.phone.request().isGranted) {
            try {
               await platform.invokeMethod('callPhoneDirect', {'number': number});
               return;
            } catch (e) {
               debugPrint("Direct call failed, falling back to dialer: $e");
            }
          }
          
          await _launchCall(number);
        } else {
             // Fallback: Open dialer with search query or empty
             await _launchCall(nameOrNumber); 
        }
      } else {
        // No contact permission, check if it's a number and we can call directly
        final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
        final isNumber = RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3;
        
        if (isNumber && await Permission.phone.request().isGranted) {
             try {
               await platform.invokeMethod('callPhoneDirect', {'number': cleanNumber});
               return;
            } catch (e) {
               debugPrint("Direct call failed, falling back to dialer: $e");
            }
        }
        
        // Just open dialer
        await _launchCall(nameOrNumber); 
      }
    } catch (e) {
      debugPrint("Failed to dial '$nameOrNumber': $e");
      // Last resort fallback
      await _launchCall(""); 
    }
  }

  Future<void> _launchCall(String number) async {
    final url = "tel:$number";
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url);
    } else {
      throw "Could not launch dialer for $number";
    }
  }



  Future<void> sendSMS(String nameOrNumber, String message) async {
     try {
      String number = nameOrNumber;
      
      // 1. Check if we need to resolve name to number
      // If it looks like a number, skip lookup
      final cleanNumber = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final isNumber = RegExp(r'^[0-9+\- ]+$').hasMatch(nameOrNumber) && cleanNumber.length >= 3;

      if (!isNumber && await Permission.contacts.request().isGranted) {
         final contacts = await FlutterContacts.getContacts(withProperties: true);
         final query = nameOrNumber.toLowerCase();
         final match = contacts.where((c) => c.displayName.toLowerCase().contains(query)).firstOrNull;
         if (match != null && match.phones.isNotEmpty) {
           number = match.phones.first.number;
         }
      }

      // 2. Try Direct SMS first
      if (await Permission.sms.request().isGranted) {
        try {
           await platform.invokeMethod('sendSMSDirect', {'number': number, 'message': message});
           return;
        } catch (e) {
           debugPrint("Direct SMS failed, falling back to app: $e");
        }
      }

      // 3. Fallback to opening SMS App
      final url = "sms:$number?body=${Uri.encodeComponent(message)}";
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        throw "Could not launch SMS app.";
      }

    } catch (e) {
      debugPrint("Failed to send SMS to '$nameOrNumber': $e");
      throw "Could not send SMS.";
    }
  }

  Future<void> toggleTorch(bool state) async {
    try {
      await platform.invokeMethod('toggleTorch', {'state': state});
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle torch: ${e.message}");
      throw "Could not toggle flashlight. ${e.message}";
    }
  }
}

/// Helper class for sorting contacts by fuzzy match score
class _ScoredContact {
  final Contact contact;
  final int distance;
  _ScoredContact(this.contact, this.distance);
}
