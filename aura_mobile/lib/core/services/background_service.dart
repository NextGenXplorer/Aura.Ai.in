import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aura_mobile/ai/run_anywhere_service.dart';
import 'package:aura_mobile/core/services/daily_summary_scheduler.dart';
import 'package:aura_mobile/features/automation/data/automation_repository.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';
import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/core/services/app_control_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Native: Background Task Started: $task");
    await _logToFile("Native: Background Task Started: $task");
    
    if (task == 'dailySummaryTask') {
      await checkAndScheduleDailySummary();
      return Future.value(true);
    }

    if (task == 'download_model_task') {
      if (inputData == null) return Future.value(false);
      
      final String url = inputData['url'];
      final String savePath = inputData['savePath'];
      final String fileName = inputData['fileName'];
      final int notificationId = inputData['notificationId'] ?? 1001;

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      final dio = Dio(BaseOptions(
        connectTimeout: Duration(minutes: 1),
        receiveTimeout: Duration(minutes: 60), // Allow long downloads
        sendTimeout: Duration(minutes: 1),
      ));
      
      try {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'download_channel',
          'Model Downloads',
          description: 'Progress of AI model downloads',
          importance: Importance.low,
        );

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        await dio.download(
          url,
          savePath,
          onReceiveProgress: (received, total) {
             if (total != -1) {
               int progress = ((received / total) * 100).toInt();
               
               if (progress % 5 == 0) { // Update every 5%
                 _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, fileName, progress, false);
                 _logToFile("Download Progress: $progress% for $fileName");
                 
                 final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
                 send?.send([url, 2, progress]);
               }
             }
          },
          deleteOnError: true,
        );

        await _logToFile("Download Success: $fileName");
        _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, fileName, 100, true);
        final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
        send?.send([url, 3, 100]);
        
        return Future.value(true);

      } catch (e) {
        print("Native: Download Failed: $e");
        await _logToFile("Native: Download Failed: $e");
        _showProgressNotification(flutterLocalNotificationsPlugin, notificationId, "Download Failed", 0, false, isError: true);
        final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
        send?.send([url, 4, 0]);
        
        return Future.value(false);
      }
    }

    // ─── Automation Rule Task Handler ───────────────────────────────────────
    if (task.startsWith(AutomationEngine.taskPrefix)) {
      final String? ruleId = inputData?['ruleId'];
      if (ruleId == null) return Future.value(false);

      final databaseHelper = DatabaseHelper();
      final automationRepository = AutomationRepository(databaseHelper);

      final rule = await automationRepository.getRule(ruleId);
      if (rule == null || !rule.isEnabled) {
        return Future.value(true);
      }

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'automation_channel',
        'Automation Rules',
        description: 'Notifications for automation rule executions',
        importance: Importance.defaultImportance,
      );
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      try {
        final prefs = await SharedPreferences.getInstance();
        final modelPath = prefs.getString('selected_model_path');

        // 1. Evaluate condition-based check via background LLM if trigger matches
        if (rule.triggerType.name == 'conditionBased') {
          final condition = rule.condition ?? '';
          if (condition.isNotEmpty) {
            final isMet = await _checkBackgroundCondition(condition, modelPath);
            if (!isMet) {
              print("Background Check: Condition '$condition' was not met. Exiting early.");
              await _logToFile("Background Check: Condition '$condition' not met for ${rule.name}");
              return Future.value(true);
            }
          }
        }

        String executionResult = '';

        // 2. Parse and run action workflow
        if (rule.actionJson != null && rule.actionJson!.isNotEmpty) {
          final actionData = jsonDecode(rule.actionJson!);
          if (actionData is Map && actionData['isWorkflow'] == true) {
            // Sequential background workflow execution
            executionResult = await _executeBackgroundWorkflow(
              Map<String, dynamic>.from(actionData as Map),
              modelPath,
              databaseHelper,
              flutterLocalNotificationsPlugin,
              ruleId,
            );
          } else {
            // Run single action fallback
            final toolCall = actionData as Map<String, dynamic>;
            final String toolName = toolCall['name'] ?? '';
            final Map<String, dynamic> arguments = toolCall['arguments'] ?? {};
            
            final appControlService = AppControlService();
            
            switch (toolName) {
              case 'toggle_torch':
                final stateArg = (arguments['state']?.toString() ?? 'on').toLowerCase();
                final state = !(stateArg == 'off' || stateArg == 'false' || stateArg == 'disable');
                await appControlService.toggleTorch(state);
                executionResult = state ? "Flashlight ON" : "Flashlight OFF";
                break;
              case 'send_sms':
                final name = arguments['name']?.toString() ?? '';
                final msg = arguments['message']?.toString() ?? '';
                await appControlService.sendSMS(name, msg);
                executionResult = "SMS sent to $name: \"$msg\"";
                break;
              case 'dial_contact':
                final contactName = arguments['contactName']?.toString() ?? '';
                await appControlService.dialContact(contactName);
                executionResult = "Calling $contactName";
                break;
              case 'open_app':
                final appName = arguments['appName']?.toString() ?? '';
                await appControlService.openApp(appName);
                executionResult = "Opened $appName";
                break;
              case 'open_settings':
                final type = arguments['type']?.toString() ?? 'general';
                await appControlService.openSettings(type);
                executionResult = "Opened $type Settings";
                break;
              case 'open_camera':
                await appControlService.openCamera();
                executionResult = "Opened Camera";
                break;
              case 'web_search':
                final query = arguments['query']?.toString() ?? '';
                await appControlService.openApp("navigate:https://www.google.com/search?q=${Uri.encodeComponent(query)}");
                executionResult = "Searched for: $query";
                break;
              default:
                executionResult = rule.actionInstruction;
            }
          }
        }

        await _logToFile("Automation Rule Executed: ${rule.name} (${rule.id})");
        print("Native: Automation Rule Executed: ${rule.name}");

        // Show execution notification
        await flutterLocalNotificationsPlugin.show(
          ruleId.hashCode,
          'AURA Automation: ${rule.name}',
          executionResult.isNotEmpty ? executionResult : rule.actionInstruction,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'automation_channel',
              'Automation Rules',
              channelDescription: 'Notifications for automation rule executions',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        );

        await automationRepository.updateLastExecutedAt(ruleId, DateTime.now());
        return Future.value(true);

      } catch (e) {
        print("Native: Automation Rule Failed: ${rule.name} - $e");
        await _logToFile("Native: Automation Rule Failed: ${rule.name} - $e");

        await flutterLocalNotificationsPlugin.show(
          ruleId.hashCode + 1,
          'Automation Failed: ${rule.name}',
          e.toString(),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'automation_channel',
              'Automation Rules',
              channelDescription: 'Notifications for automation rule executions',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );

        await automationRepository.updateLastExecutedAt(ruleId, DateTime.now());
        return Future.value(false);
      }
    }

    return Future.value(true);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> _checkBackgroundCondition(String condition, String? modelPath) async {
  if (modelPath == null || modelPath.isEmpty) {
    print("Background Check: No active model loaded. Skipping condition check.");
    return false;
  }

  try {
    final sinceMillis = DateTime.now().millisecondsSinceEpoch - 60 * 60 * 1000;
    final List<dynamic>? raw = await const MethodChannel('com.aura.ai/notifications').invokeMethod(
      'getRecentNotifications',
      {'sinceMillis': sinceMillis},
    );
    final notificationsBuffer = StringBuffer();
    if (raw != null && raw.isNotEmpty) {
      for (final item in raw) {
        final appName = item['appName'] ?? '';
        final title = item['title'] ?? '';
        final text = item['text'] ?? '';
        notificationsBuffer.writeln('- [$appName] $title: $text');
      }
    } else {
      notificationsBuffer.writeln('(No recent notifications)');
    }

    final runAnywhere = RunAnywhere();
    await runAnywhere.initialize();
    await runAnywhere.loadModel(modelPath);

    final prompt = '''
You are AURA, an on-device automation assistant.
Analyze the current device state and determine if the user's automation condition is MET.

Current Time: ${DateTime.now().toString()}
Recent Notifications:
${notificationsBuffer.toString()}

Automation Condition to Check: "$condition"

Is the condition MET? Answer with exactly YES or NO and nothing else.
''';

    final responseBuffer = StringBuffer();
    await for (final chunk in runAnywhere.chat(
      prompt: prompt,
      systemPrompt: "You are a precise binary classification model. Output only YES or NO.",
      maxTokens: 5,
      temperature: 0.1,
    )) {
      responseBuffer.write(chunk);
    }

    runAnywhere.unloadModel();

    final responseText = responseBuffer.toString().trim().toUpperCase();
    print("Background Condition Evaluated: $responseText");
    return responseText.contains('YES');
  } catch (e) {
    print("Background Condition check failed: $e");
    return false;
  }
}

Future<String> _executeBackgroundWorkflow(
    Map<String, dynamic> workflowMap,
    String? modelPath,
    DatabaseHelper dbHelper,
    FlutterLocalNotificationsPlugin notifPlugin,
    String ruleId) async {
  final stepsRaw = workflowMap['steps'] as List? ?? [];
  final context = <String, String>{};

  final appControl = AppControlService();
  final StringBuffer logs = StringBuffer();

  RunAnywhere? runAnywhere;
  bool isLlmLoaded = false;

  Future<void> ensureLlmLoaded() async {
    if (isLlmLoaded || modelPath == null || modelPath.isEmpty) return;
    try {
      runAnywhere = RunAnywhere();
      await runAnywhere!.initialize();
      await runAnywhere!.loadModel(modelPath);
      isLlmLoaded = true;
    } catch (e) {
      print("Background LLM load failed: $e");
    }
  }

  for (int i = 0; i < stepsRaw.length; i++) {
    final step = Map<String, dynamic>.from(stepsRaw[i] as Map);
    final stepId = step['id']?.toString() ?? 'step_${i + 1}';
    final stepType = step['type']?.toString() ?? '';
    final stepParams = Map<String, dynamic>.from(step['params'] as Map? ?? {});

    final resolvedParams = <String, dynamic>{};
    stepParams.forEach((key, val) {
      if (val is String) {
        resolvedParams[key] = val;
        context.forEach((cKey, cVal) {
          resolvedParams[key] = resolvedParams[key].toString().replaceAll('{$cKey}', cVal);
        });
      } else {
        resolvedParams[key] = val;
      }
    });

    String stepResult = '';
    try {
      switch (stepType) {
        case 'readClipboard':
          stepResult = '(Clipboard unavailable in background)';
          break;

        case 'readScreen':
          stepResult = '(Screen content unavailable in background)';
          break;

        case 'readNotifications':
          final sinceMillis = DateTime.now().millisecondsSinceEpoch - 60 * 60 * 1000;
          final List<dynamic>? raw = await const MethodChannel('com.aura.ai/notifications').invokeMethod(
            'getRecentNotifications',
            {'sinceMillis': sinceMillis},
          );
          if (raw != null && raw.isNotEmpty) {
            stepResult = raw.map((item) => '[${item['appName']}] ${item['title']}: ${item['text']}').join('\n');
          } else {
            stepResult = '(No notifications)';
          }
          break;

        case 'webSearch':
          final query = resolvedParams['query']?.toString() ?? '';
          if (query.isNotEmpty) {
            final dio = Dio();
            final res = await dio.get('https://html.duckduckgo.com/html/', queryParameters: {'q': query}, options: Options(headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }));
            final doc = res.data.toString();
            final matches = RegExp(r'class="result__snippet"[^>]*>([^<]+)').allMatches(doc);
            stepResult = matches.map((m) => m.group(1)?.trim() ?? '').where((s) => s.isNotEmpty).take(5).join('\n\n');
            if (stepResult.isEmpty) stepResult = '(No search results)';
          }
          break;

        case 'aiGenerate':
          final prompt = resolvedParams['prompt']?.toString() ?? '';
          if (prompt.isNotEmpty && modelPath != null) {
            await ensureLlmLoaded();
            if (runAnywhere != null && runAnywhere!.isModelLoaded) {
              final responseBuffer = StringBuffer();
              await for (final chunk in runAnywhere!.chat(
                prompt: prompt,
                systemPrompt: "You are AURA executing a background workflow step.",
                temperature: 0.3,
                maxTokens: 256,
              )) {
                responseBuffer.write(chunk);
              }
              stepResult = responseBuffer.toString().trim();
            } else {
              stepResult = '(LLM failed to load)';
            }
          }
          break;

        case 'saveMemory':
          final content = resolvedParams['content']?.toString() ?? '';
          if (content.isNotEmpty) {
            final db = await dbHelper.database;
            await db.insert('memories', {
              'id': const Uuid().v4(),
              'content': content,
              'category': 'automation',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
            stepResult = 'Saved to memory: "$content"';
          }
          break;

        case 'speakText':
          stepResult = '(TTS skipped in background)';
          break;

        case 'showNotification':
          final title = resolvedParams['title']?.toString() ?? 'AURA Flow';
          final body = resolvedParams['body']?.toString() ?? '';
          await notifPlugin.show(
            stepId.hashCode,
            title,
            body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'automation_channel',
                'Automation Rules',
                channelDescription: 'Notifications for automation rule executions',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
            ),
          );
          stepResult = 'Notification shown: $title - $body';
          break;

        case 'toggleFlashlight':
          final state = resolvedParams['state'] == true || resolvedParams['state']?.toString().toLowerCase() == 'on';
          await appControl.toggleTorch(state);
          stepResult = state ? 'Flashlight ON' : 'Flashlight OFF';
          break;

        case 'openApp':
          final app = resolvedParams['appName']?.toString() ?? '';
          await appControl.openApp(app);
          stepResult = 'Opened $app';
          break;

        case 'sendSMS':
          final contact = resolvedParams['contact']?.toString() ?? '';
          final msg = resolvedParams['message']?.toString() ?? '';
          await appControl.sendSMS(contact, msg);
          stepResult = 'Sent SMS to $contact';
          break;

        default:
          stepResult = 'Skipped unknown step: $stepType';
      }
    } catch (e) {
      stepResult = 'Failed: $e';
    }

    context[stepId] = stepResult;
    logs.writeln('${stepType}: $stepResult');
  }

  if (isLlmLoaded && runAnywhere != null) {
    try {
      runAnywhere!.unloadModel();
    } catch (e) {
      print("Failed to unload model: $e");
    }
  }

  return logs.toString().trim();
}

Future<void> _showProgressNotification(
    FlutterLocalNotificationsPlugin plugin, 
    int id, 
    String title, 
    int progress, 
    bool isComplete,
    {bool isError = false}) async {
  
  String contentText = isError ? 'Download failed.' : (isComplete ? 'Download complete.' : 'Downloading... $progress%');
  
  await plugin.show(
    id,
    'Model: $title',
    contentText,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'download_channel',
        'Model Downloads',
        channelDescription: 'Progress of AI model downloads',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        showProgress: !isComplete && !isError,
        maxProgress: 100,
        progress: progress,
        ongoing: !isComplete && !isError,
        autoCancel: false,
      ),
    ),
  );
}

Future<void> _logToFile(String message) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/background_download.log');
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString('$timestamp: $message\n', mode: FileMode.append);
  } catch (e) {
    print("Failed to write log: $e");
  }
}
