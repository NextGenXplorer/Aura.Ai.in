import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_mobile/core/services/clipboard_ai_service.dart';
import 'package:aura_mobile/core/services/notification_digest_service.dart';
import 'package:aura_mobile/features/screen_reader/screen_context_service.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

/// Privacy, permissions and network disclosure.
///
/// Several Aura features depend on permissions that could previously only be
/// granted by stumbling into a feature that silently did nothing (screen
/// reading, notification digests), or on settings with no UI at all (the
/// weather city). Features that leave the device also had no single place where
/// that was disclosed. This screen is that place.
class PrivacyPermissionsScreen extends ConsumerStatefulWidget {
  const PrivacyPermissionsScreen({super.key});

  @override
  ConsumerState<PrivacyPermissionsScreen> createState() =>
      _PrivacyPermissionsScreenState();
}

class _PrivacyPermissionsScreenState
    extends ConsumerState<PrivacyPermissionsScreen> {
  static const String cityPrefKey = 'user_city';

  final TextEditingController _cityController = TextEditingController();

  bool _loading = true;
  bool _accessibilityEnabled = false;
  bool _notificationListenerEnabled = false;
  bool _clipboardEnabled = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final digest = ref.read(notificationDigestServiceProvider);
    final clipboard = ref.read(clipboardAiServiceProvider);

    final accessibility = await ScreenContextService.checkServiceStatus();
    final listener = await digest.isListenerEnabled();

    if (!mounted) return;
    setState(() {
      _cityController.text = prefs.getString(cityPrefKey) ?? '';
      _accessibilityEnabled = accessibility;
      _notificationListenerEnabled = listener;
      _clipboardEnabled = clipboard.isEnabled;
      _loading = false;
    });
  }

  Future<void> _saveCity() async {
    final city = _cityController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (city.isEmpty) {
      await prefs.remove(cityPrefKey);
    } else {
      await prefs.setString(cityPrefKey, city);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          city.isEmpty
              ? 'City cleared. Weather falls back to New Delhi.'
              : 'Weather city set to $city.',
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
        title: Text(
          'Privacy & Permissions',
          style: GoogleFonts.outfit(
            color: ClayColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ClayColors.goldAccent),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _sectionTitle('DEVICE ACCESS'),
                _permissionCard(
                  icon: Icons.visibility_outlined,
                  title: 'Screen Reader (Accessibility)',
                  body:
                      'Needed for "read my screen" and the Read Screen automation step. '
                      'Without it those actions return an error instead of text.',
                  granted: _accessibilityEnabled,
                  actionLabel: 'Open Accessibility settings',
                  onAction: () async {
                    await ScreenContextService.openAccessibilitySettings();
                  },
                ),
                _permissionCard(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Access',
                  body:
                      'Needed for notification digests and notification-triggered '
                      'automations. Aura reads notification text only while enabled.',
                  granted: _notificationListenerEnabled,
                  actionLabel: 'Open Notification Access settings',
                  onAction: () async {
                    await ref
                        .read(notificationDigestServiceProvider)
                        .openListenerSettings();
                  },
                ),
                _clipboardCard(),

                const SizedBox(height: 8),
                _sectionTitle('WEATHER LOCATION'),
                ClayContainer(
                  borderRadius: 20,
                  depth: 4.0,
                  baseColor: ClayColors.warmGrey,
                  highlightColor: ClayColors.highlight,
                  shadowColor: ClayColors.shadow,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'City used by Daily Briefing and the home widget. '
                        'Defaults to New Delhi when empty.',
                        style: GoogleFonts.outfit(
                          color: ClayColors.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cityController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveCity(),
                        style: GoogleFonts.outfit(
                          color: ClayColors.textDark,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Bengaluru',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _saveCity,
                          child: Text(
                            'Save city',
                            style: GoogleFonts.outfit(
                              color: ClayColors.goldAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                _sectionTitle('WHAT LEAVES YOUR DEVICE'),
                _disclosureCard(),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
    child: Text(
      text,
      style: GoogleFonts.outfit(
        color: ClayColors.goldAccent,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _permissionCard({
    required IconData icon,
    required String title,
    required String body,
    required bool granted,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayContainer(
        borderRadius: 20,
        depth: 4.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: ClayColors.goldAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _statusChip(granted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: GoogleFonts.outfit(
                color: ClayColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await onAction();
                  if (!mounted) return;
                  // Status is read back on return, since the user grants the
                  // permission in system settings, not in Aura.
                  await _refresh();
                },
                child: Text(
                  actionLabel,
                  style: GoogleFonts.outfit(
                    color: ClayColors.goldAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipboardCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayContainer(
        borderRadius: 20,
        depth: 4.0,
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.content_paste_rounded,
              color: ClayColors.goldAccent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clipboard AI',
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shows an on-device suggestion bubble when you copy text, '
                    'and can trigger Clipboard Copy automations.',
                    style: GoogleFonts.outfit(
                      color: ClayColors.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _clipboardEnabled,
              activeColor: ClayColors.goldAccent,
              onChanged: (value) async {
                await ref.read(clipboardAiServiceProvider).setEnabled(value);
                if (!mounted) return;
                setState(() => _clipboardEnabled = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool granted) {
    final color = granted ? ClayColors.greenAccent : ClayColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        granted ? 'Enabled' : 'Off',
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _disclosureCard() {
    const items = <(String, String)>[
      (
        'Chat and voice with a local model',
        'Stays on device. Nothing is uploaded.',
      ),
      (
        'Chat and voice with an online provider',
        'Your prompt, chat context and any attached image are sent to the provider you configured (OpenRouter, Groq or NVIDIA NIM) using your own API key.',
      ),
      (
        'Web search and page reading',
        'The search text or URL is sent to DuckDuckGo/the site you asked about.',
      ),
      (
        'Weather, news and Daily Briefing',
        'Your configured city is sent to the weather service; headlines are fetched from Google News.',
      ),
      (
        'Image generation and meme captions',
        'The prompt is sent to Pollinations.ai to render the image.',
      ),
      (
        'Code execution',
        'Code you ask Aura to run is sent to the Wandbox online compiler.',
      ),
      ('QR codes', 'The encoded text is sent to a remote QR image generator.'),
    ];

    return ClayContainer(
      borderRadius: 20,
      depth: 4.0,
      isInset: true,
      baseColor: const Color(0xFFE5E2DA),
      highlightColor: const Color(0xFFF7F4EF),
      shadowColor: const Color(0xFFCBC7BE),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aura runs offline by default. These features need the internet, so '
            'they send the data listed below. Aura never embeds a developer API '
            'key and never uploads your chat history or documents on its own.',
            style: GoogleFonts.outfit(
              color: ClayColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          for (final (feature, detail) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: GoogleFonts.outfit(
                      color: ClayColors.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
