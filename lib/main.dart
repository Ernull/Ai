// main.dart - Nexus Link v2.0
// Complete rebuild with high-performance WebView management

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

// ============================================================================
// MAIN ENTRY
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const NexusLinkApp());
}

// ============================================================================
// APP THEME & CONFIGURATION
// ============================================================================

class AppColors {
  static const Color darkNavy = Color(0xFF0A0E21);
  static const Color deepNavy = Color(0xFF101530);
  static const Color cardNavy = Color(0xFF151A35);
  static const Color teal = Color(0xFF00BCD4);
  static const Color tealDark = Color(0xFF00838F);
  static const Color neonGreen = Color(0xFF00E676);
  static const Color neonGreenDark = Color(0xFF00C853);
  static const Color surfaceLight = Color(0xFF1C2244);
  static const Color textPrimary = Color(0xFFECEFF1);
  static const Color textSecondary = Color(0xFF90A4AE);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB40);
}

class NexusLinkApp extends StatelessWidget {
  const NexusLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexus Link',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkNavy,
        primaryColor: AppColors.teal,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.teal,
          secondary: AppColors.neonGreen,
          surface: AppColors.cardNavy,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.deepNavy,
          elevation: 0,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.teal, width: 2),
          ),
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          contentPadding: const EdgeInsets.all(20),
        ),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================================
// SERVICES - Link Extraction
// ============================================================================

class LinkExtractorService {
  static final RegExp _urlPattern = RegExp(
    r'(?:https?://)?okalav2\.up\.railway\.app[^\s\"\'\<\>\)\]\}]*',
    caseSensitive: false,
    multiLine: true,
  );

  /// Extracts and normalizes all okalav2.up.railway.app URLs from raw text.
  static List<String> extractLinks(String rawText) {
    if (rawText.trim().isEmpty) return [];

    final matches = _urlPattern.allMatches(rawText);
    final Set<String> uniqueUrls = {};

    for (final match in matches) {
      String url = match.group(0)!.trim();

      // Remove trailing punctuation that might have been captured
      url = url.replaceAll(RegExp(r'[.,;!?\s]+$'), '');

      // Normalize: ensure https:// prefix
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      // Force https
      if (url.startsWith('http://')) {
        url = url.replaceFirst('http://', 'https://');
      }

      // Decode then re-encode to normalize URL encoding
      try {
        final uri = Uri.parse(url);
        final normalized = uri.replace(
          path: Uri.decodeFull(uri.path),
        ).toString();
        uniqueUrls.add(normalized);
      } catch (_) {
        // If parsing fails, add as-is with basic normalization
        uniqueUrls.add(url);
      }
    }

    return uniqueUrls.toList();
  }
}

// ============================================================================
// SERVICES - Account Data Fetcher & Parser
// ============================================================================

class AccountData {
  final Map<String, String> localStorage;
  final List<CookieData> cookies;

  const AccountData({required this.localStorage, required this.cookies});
}

class CookieData {
  final String name;
  final String value;
  final String domain;
  final String path;

  const CookieData({
    required this.name,
    required this.value,
    this.domain = '.okala.com',
    this.path = '/',
  });
}

class AccountService {
  static final http.Client _client = http.Client();

  /// Fetches account data from the given URL and parses it.
  static Future<AccountData> fetchAccountData(String url) async {
    final response = await _client.get(Uri.parse(url)).timeout(
      const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to fetch data');
    }

    final Map<String, dynamic> json = jsonDecode(response.body);
    return _parseAccountData(json);
  }

  static AccountData _parseAccountData(Map<String, dynamic> json) {
    final Map<String, String> localStorageMap = {};
    final List<CookieData> cookiesList = [];

    // Parse localStorage from origins[0].localStorage
    if (json.containsKey('origins') && json['origins'] is List) {
      final origins = json['origins'] as List;
      if (origins.isNotEmpty && origins[0] is Map) {
        final origin = origins[0] as Map<String, dynamic>;
        if (origin.containsKey('localStorage') &&
            origin['localStorage'] is List) {
          final localStorage = origin['localStorage'] as List;
          for (final item in localStorage) {
            if (item is Map && item.containsKey('key') && item.containsKey('value')) {
              String key = item['key'].toString();
              String value = item['value'].toString();

              // Apply mutations for specific keys
              if (key == 'user' || key == 'persist:root') {
                value = _mutateStateJson(value);
              }

              localStorageMap[key] = value;
            }
          }
        }
      }
    }

    // Parse cookies - look for tokenMS and refresh_token
    if (json.containsKey('cookies') && json['cookies'] is List) {
      final cookies = json['cookies'] as List;
      for (final cookie in cookies) {
        if (cookie is Map) {
          final name = cookie['name']?.toString() ?? '';
          if (name == 'tokenMS' || name == 'refresh_token') {
            cookiesList.add(CookieData(
              name: name,
              value: cookie['value']?.toString() ?? '',
              domain: cookie['domain']?.toString() ?? '.okala.com',
              path: cookie['path']?.toString() ?? '/',
            ));
          }
        }
      }
    }

    return AccountData(localStorage: localStorageMap, cookies: cookiesList);
  }

  /// Mutates the JSON string:
  /// - "stateCode": 0 → "stateCode": 1
  /// - "customerIsLoggedInForFirstTime": true → false
  static String _mutateStateJson(String jsonString) {
    String mutated = jsonString;

    // Handle both cases: where stateCode is a number in JSON
    // and where it might be inside an escaped JSON string
    mutated = mutated.replaceAll(
      RegExp(r'"stateCode"\s*:\s*0'),
      '"stateCode": 1',
    );
    mutated = mutated.replaceAll(
      RegExp(r'"stateCode"\s*:\s*"0"'),
      '"stateCode": "1"',
    );
    // Handle escaped JSON (e.g., inside persist:root where values are stringified)
    mutated = mutated.replaceAll(
      RegExp(r'\\?"stateCode\\?"\s*:\s*0'),
      '"stateCode":1',
    );
    mutated = mutated.replaceAll(
      RegExp(r'\\"stateCode\\"\\s*:\\s*0'),
      '\\"stateCode\\":1',
    );

    // customerIsLoggedInForFirstTime: true → false
    mutated = mutated.replaceAll(
      RegExp(r'"customerIsLoggedInForFirstTime"\s*:\s*true'),
      '"customerIsLoggedInForFirstTime": false',
    );
    mutated = mutated.replaceAll(
      RegExp(r'\\"customerIsLoggedInForFirstTime\\"\\s*:\\s*true'),
      '\\"customerIsLoggedInForFirstTime\\":false',
    );

    return mutated;
  }

  static void dispose() {
    _client.close();
  }
}

// ============================================================================
// UI - HOME SCREEN
// ============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startProcessing() {
    final links = LinkExtractorService.extractLinks(_textController.text);
    if (links.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No valid okalav2.up.railway.app links found!',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ProcessingScreen(links: links),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/nexus_icon.png',
                width: 32,
                height: 32,
                errorBuilder: (_, __, ___) => Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [AppColors.teal, AppColors.neonGreen],
                    ),
                  ),
                  child: const Icon(Icons.link, size: 18, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Nexus Link',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header section
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.teal.withOpacity(0.15),
                            AppColors.neonGreen.withOpacity(0.05),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.teal.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: AppColors.neonGreen,
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Paste your text below',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Links will be extracted automatically',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Text input
                    TextField(
                      controller: _textController,
                      maxLines: 10,
                      minLines: 6,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Paste text containing okalav2.up.railway.app links...',
                        suffixIcon: _hasText
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: AppColors.textSecondary),
                                onPressed: () => _textController.clear(),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Process button
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _hasText ? _pulseAnimation.value : 1.0,
                          child: child,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: _hasText
                              ? const LinearGradient(
                                  colors: [AppColors.teal, AppColors.neonGreenDark],
                                )
                              : null,
                          color: _hasText ? null : AppColors.surfaceLight,
                          boxShadow: _hasText
                              ? [
                                  BoxShadow(
                                    color: AppColors.teal.withOpacity(0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _hasText ? _startProcessing : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.rocket_launch_rounded,
                                    color: _hasText
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Start Processing',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: _hasText
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Link count indicator
                    if (_hasText) ...[
                      const SizedBox(height: 16),
                      Builder(builder: (_) {
                        final count = LinkExtractorService.extractLinks(
                          _textController.text,
                        ).length;
                        return AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: count > 0
                                    ? AppColors.neonGreen.withOpacity(0.15)
                                    : AppColors.error.withOpacity(0.15),
                              ),
                              child: Text(
                                '$count link${count != 1 ? 's' : ''} detected',
                                style: TextStyle(
                                  color: count > 0
                                      ? AppColors.neonGreen
                                      : AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.deepNavy,
                border: Border(
                  top: BorderSide(
                    color: AppColors.teal.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded,
                      size: 18, color: AppColors.teal.withOpacity(0.8)),
                  const SizedBox(width: 8),
                  Text(
                    'ساخته شده توسط @OkalaLink',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ANIMATED BUILDER HELPER (for pulse animation)
// ============================================================================

class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

// ============================================================================
// STATE ENUMERATION
// ============================================================================

enum ProcessingState { idle, fetching, injecting, loaded, error }

// ============================================================================
// UI - PROCESSING SCREEN (Single WebView Instance)
// ============================================================================

class ProcessingScreen extends StatefulWidget {
  final List<String> links;

  const ProcessingScreen({super.key, required this.links});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin {
  // State management with ValueNotifier to avoid unnecessary rebuilds
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);
  final ValueNotifier<ProcessingState> _state =
      ValueNotifier<ProcessingState>(ProcessingState.idle);
  final ValueNotifier<String> _statusMessage =
      ValueNotifier<String>('Ready to process');
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);

  InAppWebViewController? _webViewController;
  final CookieManager _cookieManager = CookieManager.instance();

  late AnimationController _loadingAnimController;
  late Animation<double> _loadingAnimation;

  @override
  void initState() {
    super.initState();
    _loadingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      _loadingAnimController,
    );

    // Auto-start first account
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.links.isNotEmpty) {
        _processCurrentAccount();
      }
    });
  }

  @override
  void dispose() {
    _currentIndex.dispose();
    _state.dispose();
    _statusMessage.dispose();
    _progress.dispose();
    _loadingAnimController.dispose();
    super.dispose();
  }

  Future<void> _processCurrentAccount() async {
    final index = _currentIndex.value;
    if (index >= widget.links.length) return;

    _state.value = ProcessingState.fetching;
    _statusMessage.value = 'Fetching account data...';
    _progress.value = 0.2;

    try {
      // Step 1: Fetch account data
      final accountData =
          await AccountService.fetchAccountData(widget.links[index]);

      _state.value = ProcessingState.injecting;
      _statusMessage.value = 'Injecting cookies & storage...';
      _progress.value = 0.5;

      // Step 2: Clear existing data
      await _cookieManager.deleteAllCookies();

      if (_webViewController != null) {
        // Clear localStorage
        await _webViewController!.evaluateJavascript(
          source: 'localStorage.clear(); sessionStorage.clear();',
        );
      }

      // Step 3: Inject cookies
      for (final cookie in accountData.cookies) {
        await _cookieManager.setCookie(
          url: WebUri('https://www.okala.com/'),
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path,
          isSecure: true,
          isHttpOnly: false,
        );
      }

      _progress.value = 0.7;

      // Step 4: Inject localStorage via JavaScript
      if (_webViewController != null && accountData.localStorage.isNotEmpty) {
        final StringBuffer jsCode = StringBuffer();
        for (final entry in accountData.localStorage.entries) {
          // Properly escape for JavaScript
          final escapedKey = _escapeJs(entry.key);
          final escapedValue = _escapeJs(entry.value);
          jsCode.writeln(
              "localStorage.setItem('$escapedKey', '$escapedValue');");
        }
        await _webViewController!.evaluateJavascript(source: jsCode.toString());
      }

      _progress.value = 0.85;
      _statusMessage.value = 'Loading Okala...';

      // Step 5: Navigate to okala.com (reuse WebView - no rebuild!)
      if (_webViewController != null) {
        await _webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri('https://www.okala.com/')),
        );
      }

      _state.value = ProcessingState.loaded;
      _statusMessage.value = 'Account ${index + 1} loaded ✓';
      _progress.value = 1.0;
    } catch (e) {
      _state.value = ProcessingState.error;
      _statusMessage.value = 'Error: ${e.toString().substring(0, 80)}';
      _progress.value = 0.0;
    }
  }

  void _nextAccount() {
    if (_currentIndex.value < widget.links.length - 1) {
      _currentIndex.value++;
      _processCurrentAccount();
    }
  }

  void _previousAccount() {
    if (_currentIndex.value > 0) {
      _currentIndex.value--;
      _processCurrentAccount();
    }
  }

  String _escapeJs(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: ValueListenableBuilder<int>(
          valueListenable: _currentIndex,
          builder: (_, index, __) => Text(
            'Account ${index + 1} / ${widget.links.length}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: _currentIndex,
            builder: (_, index, __) => Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: index > 0 ? _previousAccount : null,
                  tooltip: 'Previous',
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed:
                      index < widget.links.length - 1 ? _nextAccount : null,
                  tooltip: 'Next',
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(),

          // WebView - single instance, never destroyed
          Expanded(
            child: ClipRRect(
              child: InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri('about:blank')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  clearSessionCache: false,
                  userAgent:
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  supportZoom: true,
                  allowContentAccess: true,
                  allowFileAccess: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStop: (controller, url) {
                  if (url.toString().contains('okala.com')) {
                    _state.value = ProcessingState.loaded;
                    _progress.value = 1.0;
                  }
                },
                onReceivedError: (controller, request, error) {
                  debugPrint('WebView error: ${error.description}');
                },
              ),
            ),
          ),

          // Bottom navigation
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return ValueListenableBuilder<ProcessingState>(
      valueListenable: _state,
      builder: (_, state, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.deepNavy,
            border: Border(
              bottom: BorderSide(
                color: _stateColor(state).withOpacity(0.4),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Animated status indicator
              _buildStateIndicator(state),
              const SizedBox(width: 12),
              // Status message
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: _statusMessage,
                  builder: (_, message, __) => Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStateIndicator(ProcessingState state) {
    if (state == ProcessingState.fetching || state == ProcessingState.injecting) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonGreen),
        ),
      );
    }
    IconData icon = Icons.info_outline;
    if (state == ProcessingState.loaded) icon = Icons.check_circle_rounded;
    if (state == ProcessingState.error) icon = Icons.error_outline_rounded;
    
    return Icon(icon, size: 18, color: _stateColor(state));
  }

  Color _stateColor(ProcessingState state) {
    switch (state) {
      case ProcessingState.error: return AppColors.error;
      case ProcessingState.loaded: return AppColors.neonGreen;
      case ProcessingState.fetching:
      case ProcessingState.injecting: return AppColors.teal;
      default: return AppColors.textSecondary;
    }
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: AppColors.deepNavy,
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (_, progress, __) => LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.surfaceLight,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonGreen),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

