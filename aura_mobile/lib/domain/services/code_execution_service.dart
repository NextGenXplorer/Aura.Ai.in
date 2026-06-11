import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// Executes code via the Wandbox API (https://wandbox.org) — free, no auth.
///
/// Supports 30+ languages: Python, JavaScript, TypeScript, C, C++, C#, Java,
/// Go, Rust, Ruby, PHP, Swift, Bash, Lua, Perl, R, Haskell, Scala, and more.
///
/// Note: The previous Piston public API (emkc.org) became whitelist-only as
/// of Feb 2026, so Wandbox is now the primary execution engine.
class CodeExecutionService {
  final Logger _logger = Logger();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://wandbox.org/api',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'AuraMobile/1.0',
    },
    validateStatus: (status) => status != null && status < 500,
  ));

  /// Maps common language names/aliases to Wandbox compiler identifiers.
  /// These are stable compiler names verified against the Wandbox compiler list.
  static const Map<String, String> _compilerMap = {
    // Python
    'python': 'cpython-3.12.7',
    'python3': 'cpython-3.12.7',
    'py': 'cpython-3.12.7',
    'python2': 'cpython-2.7.18',
    'py2': 'cpython-2.7.18',
    // JavaScript / TypeScript
    'javascript': 'nodejs-20.17.0',
    'js': 'nodejs-20.17.0',
    'node': 'nodejs-20.17.0',
    'typescript': 'typescript-5.6.2',
    'ts': 'typescript-5.6.2',
    // C / C++
    'c': 'gcc-13.2.0-c',
    'cpp': 'gcc-13.2.0',
    'c++': 'gcc-13.2.0',
    // C#
    'csharp': 'dotnetcore-8.0.402',
    'c#': 'dotnetcore-8.0.402',
    'cs': 'dotnetcore-8.0.402',
    // Other languages
    'rust': 'rust-1.82.0',
    'rs': 'rust-1.82.0',
    'go': 'go-1.23.2',
    'golang': 'go-1.23.2',
    'ruby': 'ruby-3.4.9',
    'rb': 'ruby-3.4.9',
    'php': 'php-8.3.12',
    'bash': 'bash',
    'sh': 'bash',
    'shell': 'bash',
    'lua': 'lua-5.4.7',
    'perl': 'perl-5.40.0',
    'pl': 'perl-5.40.0',
    'r': 'r-4.4.1',
    'java': 'openjdk-jdk-22+36',
    'haskell': 'ghc-9.10.1',
    'hs': 'ghc-9.10.1',
    'scala': 'scala-3.5.1',
    'swift': 'swift-6.0.1',
    'pascal': 'fpc-3.2.2',
    'lisp': 'sbcl-2.4.9',
    'sql': 'sqlite-3.46.1',
    'sqlite': 'sqlite-3.46.1',
  };

  /// Returns true if a language can be executed online.
  bool isSupported(String language) {
    return _compilerMap.containsKey(language.toLowerCase().trim());
  }

  /// Executes code and returns the output (or error message).
  Future<String> executeCode(String code, String language) async {
    final lang = language.toLowerCase().trim();
    final compiler = _compilerMap[lang];

    if (compiler == null) {
      return "Language '$language' isn't supported for online execution.\n\n"
          "Supported: Python, JavaScript, TypeScript, C, C++, C#, Java, "
          "Go, Rust, Ruby, PHP, Swift, Bash, Lua, Perl, R, Haskell, Scala, and more.";
    }

    try {
      final payload = {
        'code': code,
        'compiler': compiler,
        'stdin': '',
        // Compiler options for languages that need them
        if (lang == 'c' || lang == 'cpp' || lang == 'c++')
          'options': 'warning,gnu++17',
      };

      final response = await _dio.post('/compile.json', data: payload);

      if (response.statusCode == 200) {
        return _parseWandboxResponse(response.data);
      } else if (response.statusCode == 400) {
        return "Compilation failed — please check your code syntax.";
      } else {
        throw Exception("HTTP ${response.statusCode}");
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return "Execution timed out. The program took too long or the server is busy.";
      }
      _logger.w("Wandbox execution failed: ${e.message}");
      return "Couldn't reach the execution server.\nTry switching between WiFi and mobile data, then try again.";
    } catch (e) {
      _logger.e("Code execution error: $e");
      return "Something went wrong while running the code. Please try again.";
    }
  }

  /// Parses Wandbox's JSON response into a clean output string.
  String _parseWandboxResponse(dynamic data) {
    if (data is! Map) return "Unexpected response from execution server.";

    final output = StringBuffer();

    final compilerError = data['compiler_error']?.toString() ?? '';
    final programOutput = data['program_output']?.toString() ?? '';
    final programError = data['program_error']?.toString() ?? '';

    // Compilation errors take priority
    if (compilerError.trim().isNotEmpty) {
      output.writeln("--- Compilation Error ---");
      output.write(compilerError.trim());
      return output.toString().trim();
    }

    // Program output
    if (programOutput.trim().isNotEmpty) {
      output.write(programOutput.trimRight());
    }

    // Runtime errors
    if (programError.trim().isNotEmpty) {
      if (output.isNotEmpty) output.writeln();
      output.writeln("--- Runtime Error ---");
      output.write(programError.trim());
    }

    final result = output.toString().trim();
    return result.isEmpty ? "(Program ran successfully with no output)" : result;
  }
}
