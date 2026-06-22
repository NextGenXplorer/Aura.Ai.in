import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class VoiceAssistantSettingsPage extends StatefulWidget {
  const VoiceAssistantSettingsPage({super.key});

  @override
  State<VoiceAssistantSettingsPage> createState() =>
      _VoiceAssistantSettingsPageState();
}

class _VoiceAssistantSettingsPageState
    extends State<VoiceAssistantSettingsPage> with WidgetsBindingObserver {
  // Permission statuses — null = loading
  final Map<String, PermissionStatus?> _statuses = {
    'microphone': null,
    'contacts': null,
    'phone': null,
    'sms': null,
    'camera': null,
    'notification': null,
    'systemAlertWindow': null,
  };

  // Gesture mode: 'shake', 'power', or 'both'
  String _gestureMode = 'both';

  static const _gesturePrefKey = 'va_gesture_mode';
  static const MethodChannel _channel =
      MethodChannel('com.aura.ai/app_control');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Refresh statuses whenever the app resumes (user coming back from settings)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAll();
  }

  Future<void> _loadAll() async {
    await _refreshPermissions();
    await _loadGestureMode();
  }

  Future<void> _refreshPermissions() async {
    final mic = await Permission.microphone.status;
    final contacts = await Permission.contacts.status;
    final phone = await Permission.phone.status;
    final sms = await Permission.sms.status;
    final camera = await Permission.camera.status;
    final notif = await Permission.notification.status;
    final overlay = await Permission.systemAlertWindow.status;

    if (mounted) {
      setState(() {
        _statuses['microphone'] = mic;
        _statuses['contacts'] = contacts;
        _statuses['phone'] = phone;
        _statuses['sms'] = sms;
        _statuses['camera'] = camera;
        _statuses['notification'] = notif;
        _statuses['systemAlertWindow'] = overlay;
      });
    }
  }

  Future<void> _loadGestureMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_gesturePrefKey) ?? 'both';
    if (mounted) setState(() => _gestureMode = saved);
    _applyGestureMode(saved);
  }

  Future<void> _saveGestureMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gesturePrefKey, mode);
    setState(() => _gestureMode = mode);
    _applyGestureMode(mode);
  }

  void _applyGestureMode(String mode) {
    // Notify the native side which gestures to enable
    try {
      _channel.invokeMethod('setGestureMode', {'mode': mode});
    } catch (_) {}
  }

  /// Tap handler: ask permission, or open settings if permanently denied
  Future<void> _handlePermissionTap(Permission permission) async {
    final status = await permission.status;
    if (status.isPermanentlyDenied || status.isRestricted) {
      // Send user to app settings
      await openAppSettings();
    } else if (status.isDenied) {
      // For system alert window, use native intent
      if (permission == Permission.systemAlertWindow) {
        try {
          await _channel.invokeMethod('requestOverlayPermission');
        } catch (_) {
          await openAppSettings();
        }
      } else {
        await permission.request();
      }
    }
    await _refreshPermissions();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPermissionCard({
    required String label,
    required String description,
    required IconData icon,
    required String key,
    required Permission permission,
  }) {
    final status = _statuses[key];
    final bool? granted = status?.isGranted;
    final isPermanent = status?.isPermanentlyDenied ?? false;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (granted == null) {
      statusColor = ClayColors.textMuted;
      statusText = 'Checking…';
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (granted) {
      statusColor = ClayColors.greenAccent;
      statusText = 'Granted';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = ClayColors.redAccent;
      statusText = isPermanent ? 'Permanently Denied' : 'Denied';
      statusIcon = Icons.cancel_rounded;
    }

    final Color cardBorderColor = granted == true
        ? ClayColors.greenAccent.withOpacity(0.2)
        : granted == false
            ? ClayColors.redAccent.withOpacity(0.2)
            : Colors.black.withOpacity(0.03);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: ClayContainer(
        borderRadius: 20,
        depth: 4.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        border: Border.all(color: cardBorderColor, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icon leading in sunken card
            ClayContainer(
              width: 44,
              height: 44,
              borderRadius: 12,
              isInset: true,
              depth: 3.0,
              baseColor: const Color(0xFFE5E2DA),
              highlightColor: const Color(0xFFF7F4EF),
              shadowColor: const Color(0xFFCBC7BE),
              child: Center(
                child: Icon(icon, color: ClayColors.goldAccent, size: 20),
              ),
            ),
            const SizedBox(width: 14),

            // Text Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: GoogleFonts.outfit(
                          color: statusColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Action Button Trailing
            if (granted != true)
              ClayButton(
                onTap: () => _handlePermissionTap(permission),
                borderRadius: 10,
                depth: 3.0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                baseColor: ClayColors.goldHighlight,
                highlightColor: const Color(0xFFFFF7F5),
                shadowColor: ClayColors.goldShadow,
                child: Text(
                  isPermanent ? 'Settings' : 'Allow',
                  style: GoogleFonts.outfit(
                    color: ClayColors.goldAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureOption({
    required String value,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _gestureMode == value;

    final Color base = selected ? ClayColors.goldHighlight : ClayColors.warmGrey;
    final Color highlight = selected ? const Color(0xFFFFF7F5) : ClayColors.highlight;
    final Color shadow = selected ? ClayColors.goldShadow : ClayColors.shadow;
    final Color accent = selected ? ClayColors.goldAccent : ClayColors.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClayButton(
        onTap: () => _saveGestureMode(value),
        borderRadius: 18,
        depth: selected ? 3.0 : 5.0,
        baseColor: base,
        highlightColor: highlight,
        shadowColor: shadow,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: accent,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: selected ? ClayColors.goldAccent : ClayColors.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: ClayColors.goldAccent, size: 20)
            else
              Icon(Icons.circle_outlined, color: Colors.black.withOpacity(0.12), size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ClayColors.textDark),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ClayColors.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Voice Assistant Settings',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: ClayColors.goldAccent, size: 22),
            tooltip: 'Refresh permissions',
            onPressed: _refreshPermissions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          // ── Permissions Section ──────────────────────────────────────────
          _sectionHeader('Required Permissions', Icons.security_rounded),
          const SizedBox(height: 12),

          _buildPermissionCard(
            key: 'microphone',
            label: 'Microphone',
            description: 'Needed to hear your voice commands',
            icon: Icons.mic_rounded,
            permission: Permission.microphone,
          ),
          _buildPermissionCard(
            key: 'contacts',
            label: 'Contacts',
            description: 'Required to find contacts when calling or messaging',
            icon: Icons.contacts_rounded,
            permission: Permission.contacts,
          ),
          _buildPermissionCard(
            key: 'phone',
            label: 'Phone (Make Calls)',
            description: 'Allows AURA to initiate calls directly',
            icon: Icons.phone_rounded,
            permission: Permission.phone,
          ),
          _buildPermissionCard(
            key: 'sms',
            label: 'SMS / Messages',
            description: 'Allows AURA to send messages on your behalf',
            icon: Icons.sms_rounded,
            permission: Permission.sms,
          ),
          _buildPermissionCard(
            key: 'camera',
            label: 'Camera',
            description: 'Used when you say "open camera"',
            icon: Icons.camera_alt_rounded,
            permission: Permission.camera,
          ),
          _buildPermissionCard(
            key: 'notification',
            label: 'Notifications',
            description: 'Required to show the persistent service notification',
            icon: Icons.notifications_rounded,
            permission: Permission.notification,
          ),
          _buildPermissionCard(
            key: 'systemAlertWindow',
            label: 'Display Over Other Apps',
            description:
                'Critical — allows the AURA overlay to appear above everything',
            icon: Icons.picture_in_picture_alt_rounded,
            permission: Permission.systemAlertWindow,
          ),

          const SizedBox(height: 24),

          // ── Gesture Section ──────────────────────────────────────────────
          _sectionHeader('Activation Gesture', Icons.touch_app_rounded),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2),
            child: Text(
              'Choose how to wake up AURA when the app is in the background',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13, height: 1.35),
            ),
          ),

          _buildGestureOption(
            value: 'shake',
            label: 'Shake to Activate',
            subtitle: 'Shake your phone to trigger the assistant',
            icon: Icons.vibration_rounded,
          ),
          _buildGestureOption(
            value: 'power',
            label: 'Double Power Button',
            subtitle:
                'Press power button twice quickly (disable camera shortcut in OEM settings first)',
            icon: Icons.power_settings_new_rounded,
          ),
          _buildGestureOption(
            value: 'both',
            label: 'Both Gestures',
            subtitle: 'Shake or double power button — either works',
            icon: Icons.auto_awesome_rounded,
          ),

          const SizedBox(height: 16),
          _oneplusNote(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: ClayColors.goldAccent, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: ClayColors.goldAccent,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _oneplusNote() {
    return ClayContainer(
      borderRadius: 16,
      depth: 3.0,
      baseColor: ClayColors.warmGrey,
      highlightColor: ClayColors.highlight,
      shadowColor: ClayColors.shadow,
      border: Border.all(color: ClayColors.blueAccent.withOpacity(0.15), width: 1.0),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: ClayColors.blueAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'OnePlus tip: If double power button doesn\'t work, go to Settings → Buttons & Gestures → Quick Launch and disable the Camera shortcut.',
              style: GoogleFonts.outfit(
                color: ClayColors.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
