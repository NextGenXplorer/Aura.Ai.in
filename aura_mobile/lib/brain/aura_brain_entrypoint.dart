import 'dart:async';
import 'dart:ui';

import 'package:aura_mobile/core/providers/ai_providers.dart';
import 'package:aura_mobile/presentation/providers/model_selector_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'aura_brain_controller.dart';

@pragma('vm:entry-point')
void auraBrainMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final container = ProviderContainer();
  final controller = AuraBrainController(
    // The exported Brain protocol is contractually local-only and must never
    // inherit Aura's interactive online-provider selection.
    llmService: container.read(liteRtServiceProvider),
    modelManager: container.read(modelManagerProvider),
    ownsRuntime: true,
    onDispose: container.dispose,
  );
  unawaited(controller.initialize());
}
