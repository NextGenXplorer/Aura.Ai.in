import 'package:aura_mobile/core/services/device_service.dart';
import 'package:aura_mobile/domain/services/model_recommendation_service.dart';
import 'package:aura_mobile/presentation/pages/online_provider_settings_screen.dart';
import 'package:aura_mobile/domain/entities/model_info.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/core/services/download_service.dart';
import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();

  // State
  DeviceInfo? _deviceInfo;
  List<ModelInfo> _recommendations = [];
  String? _selectedModelId;

  Future<void> _analyzeDevice() async {
    // Artificial delay for UX "Scanning" effect
    await Future.delayed(const Duration(seconds: 2));

    final deviceService = ref.read(deviceServiceProvider);
    final recService = ref.read(modelRecommendationServiceProvider);

    try {
      final info = await deviceService.analyzeDevice();
      final recs = recService.getRecommendations(info);

      if (mounted) {
        setState(() {
          _deviceInfo = info;
          _recommendations = recs;
        });
        _pageController.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.ease,
        );
      }
    } catch (e) {
      debugPrint("Analysis failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildWelcomeStep(),
          _buildAnalysisStep(),
          _buildRecommendationStep(),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClayContainer(
            borderRadius: 32,
            depth: 8,
            padding: const EdgeInsets.all(24),
            baseColor: ClayColors.warmGrey,
            highlightColor: ClayColors.highlight,
            shadowColor: ClayColors.shadow,
            child: const Icon(
              Icons.shield_moon_outlined,
              size: 56,
              color: ClayColors.goldAccent,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            "Welcome to AURA",
            style: GoogleFonts.outfit(
              color: ClayColors.textDark,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Your private, offline AI assistant.\nLet's get to know you.",
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: ClayColors.textMuted,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 48),
          ClayTextField(
            controller: _nameController,
            hintText: "Enter your name",
            prefixIcon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 32),
          ClayButton(
            onTap: () {
              if (_nameController.text.trim().isNotEmpty) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.ease,
                );
                _analyzeDevice();
              }
            },
            baseColor: ClayColors.goldAccent,
            highlightColor: ClayColors.goldHighlight,
            shadowColor: ClayColors.goldShadow,
            child: const Center(
              child: Text(
                "Next",
                style: TextStyle(
                  color: ClayColors.goldHighlight,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: ClayContainer(
          borderRadius: 28,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: ClayColors.goldAccent,
                  strokeWidth: 3.5,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "Analyzing Hardware",
                style: GoogleFonts.outfit(
                  color: ClayColors.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Detecting optimized engine support...",
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 13,
                ),
              ),
              if (_deviceInfo != null) ...[
                const SizedBox(height: 24),
                ClayContainer(
                  borderRadius: 16,
                  isInset: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  baseColor: const Color(0xFFE5E2DA),
                  highlightColor: const Color(0xFFF7F4EF),
                  shadowColor: const Color(0xFFCBC7BE),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "RAM Capacity",
                            style: GoogleFonts.outfit(
                              color: ClayColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "${_deviceInfo!.totalRamMB} MB",
                            style: GoogleFonts.outfit(
                              color: ClayColors.textDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.black12, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Architecture",
                            style: GoogleFonts.outfit(
                              color: ClayColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _deviceInfo!.isArm64
                                ? 'ARM64 Supported'
                                : 'Unsupported',
                            style: GoogleFonts.outfit(
                              color: ClayColors.textDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Hello, ${_nameController.text}",
              style: GoogleFonts.outfit(
                color: ClayColors.textDark,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Based on your hardware capabilities,\nwe recommend installing these local models:",
              style: GoogleFonts.outfit(
                color: ClayColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  final model = _recommendations[index];
                  final isSelected = _selectedModelId == model.id;

                  String badgeLabel = "";
                  Color badgeColor = Colors.transparent;

                  if (model.id.contains('smollm')) {
                    badgeLabel = "Lightweight";
                    badgeColor = ClayColors.greenAccent;
                  } else if (model.id.contains('mistral') ||
                      model.id.contains('llama-3')) {
                    badgeLabel = "Optimal Performance";
                    badgeColor = ClayColors.goldAccent;
                  } else {
                    badgeLabel = "Balanced";
                    badgeColor = ClayColors.blueAccent;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ClayButton(
                      onTap: () {
                        setState(() => _selectedModelId = model.id);
                      },
                      padding: const EdgeInsets.all(20.0),
                      borderRadius: 22,
                      baseColor: isSelected
                          ? ClayColors.goldHighlight
                          : ClayColors.warmGrey,
                      highlightColor: isSelected
                          ? const Color(0xFFFFFFFF)
                          : ClayColors.highlight,
                      shadowColor: isSelected
                          ? ClayColors.goldShadow
                          : ClayColors.shadow,
                      depth: isSelected ? 3 : 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: badgeColor.withOpacity(0.3),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  badgeLabel,
                                  style: GoogleFonts.outfit(
                                    color: badgeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Text(
                                model.sizeFormatted,
                                style: GoogleFonts.outfit(
                                  color: ClayColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            model.name,
                            style: GoogleFonts.outfit(
                              color: isSelected
                                  ? ClayColors.goldAccent
                                  : ClayColors.textDark,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            model.description,
                            style: GoogleFonts.outfit(
                              color: ClayColors.textMuted,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 20),
                            if (_isDownloading && _downloadTaskId != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ClayProgressBar(
                                    value: _downloadProgress / 100,
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: Text(
                                      "$downloadStatusText",
                                      style: GoogleFonts.outfit(
                                        color: ClayColors.goldAccent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              ClayButton(
                                onTap: _isDownloading
                                    ? null
                                    : () => _startDownload(model),
                                baseColor: ClayColors.goldAccent,
                                highlightColor: ClayColors.goldHighlight,
                                shadowColor: ClayColors.goldShadow,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: const Center(
                                  child: Text(
                                    "Download & Start",
                                    style: TextStyle(
                                      color: ClayColors.goldHighlight,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            ClayButton(
              onTap: _isDownloading ? null : _continueWithOnlineProvider,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  "Skip download — use an online API key",
                  style: GoogleFonts.outfit(
                    color: ClayColors.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                "Online models need an API key you create. Local models keep everything on-device.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: ClayColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "Hardware Specs: Total RAM ${_deviceInfo?.totalRamMB}MB | Free ${_deviceInfo?.availableRamMB}MB",
                style: GoogleFonts.outfit(
                  color: ClayColors.textHint,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Download State
  bool _isDownloading = false;
  String? _downloadTaskId;
  int _downloadProgress = 0;
  String downloadStatusText = "Starting...";

  Future<void> _startDownload(ModelInfo model) async {
    // 1. Request Notification Permission (Android 13+)
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
      if (!status.isGranted) {
        // Show warning but proceed (download might still work in background, just no notif)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Warning: Notifications disabled. Download will run silently in background.",
              ),
            ),
          );
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      downloadStatusText = "Starting...";
    });

    try {
      // Get strict path
      final directory = await getApplicationDocumentsDirectory();

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = "${directory.path}/${model.fileName}";

      // Start Download via DownloadService (which wraps FlutterForegroundTask)
      // Debug Print
      print("DEBUG: Requesting download for ${model.url} to $filePath");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download Request Sent: ${model.name}")),
        );
      }

      final downloadService = DownloadService();
      await downloadService.initialize();
      final taskId = await downloadService.downloadModel(model.url, filePath);

      if (taskId != null) {
        setState(() => _downloadTaskId = taskId);

        // Listen to updates
        downloadService.downloadUpdates.listen((update) {
          print(
            "DEBUG: UI Received Update: ${update.id} - ${update.status} - ${update.progress}",
          );
          if (update.id == taskId) {
            if (mounted) {
              setState(() {
                _downloadProgress = update.progress;
                if (update.status == DownloadTaskStatus.running) {
                  downloadStatusText = "Downloading... ${update.progress}%";
                } else if (update.status == DownloadTaskStatus.complete) {
                  downloadStatusText = "Finalizing...";
                  _finalizeOnboarding(model, filePath);
                } else if (update.status == DownloadTaskStatus.failed) {
                  downloadStatusText = "Failed. Retrying...";
                  _isDownloading = false;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Download Failed. Please check internet connection.",
                      ),
                    ),
                  );
                }
              });
            }
          }
        });
      }
    } catch (e) {
      print("Download error: $e");
      if (mounted) {
        setState(() {
          _isDownloading = false;
          downloadStatusText = "Error: $e";
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error starting download: $e")));
      }
    }
  }

  /// Lets a first-time user start with an online provider key instead of
  /// waiting for a multi-GB local model download.
  Future<void> _continueWithOnlineProvider() async {
    final router = ref.read(llmRouterProvider);
    try {
      await router.initialize();
    } catch (e) {
      debugPrint('Runtime init before online setup failed: $e');
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnlineProviderSettingsScreen()),
    );
    if (!mounted) return;

    if (!router.isOnline || !router.isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a provider key and tap Use on a model to continue online.',
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    await prefs.setBool('is_onboarded', true);
    if (mounted) Navigator.of(context).pushReplacementNamed('/chat');
  }

  Future<void> _finalizeOnboarding(ModelInfo model, String path) async {
    // Save prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    await prefs.setBool('is_onboarded', true);

    // Initialize and atomically persist the downloaded local model.
    try {
      final router = ref.read(llmRouterProvider);
      await router.initialize();
      await router.selectLocalModel(
        model: model,
        path: path,
        deviceService: ref.read(deviceServiceProvider),
      );
    } catch (e) {
      print("Auto-load failed: $e");
    }

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/chat');
    }
  }
}
