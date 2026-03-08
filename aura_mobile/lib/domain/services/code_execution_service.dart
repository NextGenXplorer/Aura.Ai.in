import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class CodeExecutionService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://emkc.org/api/v2/piston',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  final Logger _logger = Logger();

  // Cache fetched runtimes
  List<Map<String, dynamic>>? _runtimes;

  /// Fetches available languages from Piston
  Future<List<Map<String, dynamic>>> getRuntimes() async {
    if (_runtimes != null) return _runtimes!;
    try {
      final response = await _dio.get('/runtimes');
      if (response.statusCode == 200) {
        _runtimes = List<Map<String, dynamic>>.from(response.data);
        return _runtimes!;
      }
    } catch (e) {
      _logger.e("Failed to fetch Piston runtimes: $e");
    }
    return [];
  }

  /// Finds the correct Piston language configuration based on common markdown names
  Future<Map<String, dynamic>?> _resolveLanguage(String languageKey) async {
    final runtimes = await getRuntimes();
    final lowerKey = languageKey.toLowerCase().trim();

    for (var runtime in runtimes) {
      final lang = runtime['language'] as String;
      final aliases = List<String>.from(runtime['aliases'] ?? []);
      if (lang == lowerKey || aliases.contains(lowerKey)) {
        return runtime;
      }
    }
    
    // Quick fallback aliases
    if (lowerKey == 'js' || lowerKey == 'javascript' || lowerKey == 'node') return runtimes.firstWhere((r) => r['language'] == 'javascript', orElse: () => <String, dynamic>{});
    if (lowerKey == 'ts' || lowerKey == 'typescript') return runtimes.firstWhere((r) => r['language'] == 'typescript', orElse: () => <String, dynamic>{});
    if (lowerKey == 'py' || lowerKey == 'python') return runtimes.firstWhere((r) => r['language'] == 'python', orElse: () => <String, dynamic>{});
    if (lowerKey == 'cpp' || lowerKey == 'c++') return runtimes.firstWhere((r) => r['language'] == 'c++', orElse: () => <String, dynamic>{});

    return null;
  }

  /// Executes code using the Piston v2 API
  Future<String> executeCode(String code, String language) async {
    try {
      final runtime = await _resolveLanguage(language);
      if (runtime == null || runtime.isEmpty) {
        return "Error: Language '$language' is not supported by the execution engine.";
      }

      final payload = {
        "language": runtime['language'],
        "version": runtime['version'],
        "files": [
          {
            "content": code
          }
        ],
        "stdin": "",
        "args": [],
        "compile_timeout": 10000,
        "run_timeout": 5000,
        "compile_memory_limit": -1,
        "run_memory_limit": -1
      };

      final response = await _dio.post('/execute', data: payload);

      if (response.statusCode == 200) {
        final data = response.data;
        final runResult = data['run'];
        final compileResult = data['compile'];

        StringBuffer output = StringBuffer();
        
        if (compileResult != null && compileResult['code'] != 0) {
          output.writeln("--- Compilation Error ---");
          output.writeln(compileResult['output'] ?? "");
        } else if (runResult != null) {
          final stdout = runResult['stdout'] ?? "";
          final stderr = runResult['stderr'] ?? "";
          output.write(stdout);
          if (stderr.toString().isNotEmpty) {
             output.writeln("\n--- Error Output ---");
             output.writeln(stderr);
          }
        } else {
           output.writeln("Unknown execution error. Data: $data");
        }
        
        return output.toString().trim();
      } else {
        return "Engine returned status code: ${response.statusCode}\n${response.data}";
      }

    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        return "Execution timed out. The server took too long to respond.";
      }
      return "Network error: ${e.message}";
    } catch (e) {
      _logger.e("Error executing code: $e");
      return "Internal error occurred while trying to run the code: $e";
    }
  }
}
