import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusLinkApp());
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
        scaffoldBackgroundColor: NexusColors.navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: NexusColors.teal,
          brightness: Brightness.dark,
        ).copyWith(
          primary: NexusColors.teal,
          secondary: NexusColors.green,
          surface: NexusColors.panel,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class NexusColors {
  static const navy = Color(0xFF0A0E21);
  static const panel = Color(0xFF111A35);
  static const teal = Color(0xFF00BCD4);
  static const green = Color(0xFF00E676);
  static const muted = Color(0xFF8C9AB8);
  static const border = Color(0x3348D9E8);
}

class LinkExtractor {
  static final RegExp railwayLink = RegExp(
    r'https?://okalav2\.up\.railway\.app(?:/[^\s<>"\x27]*)?',
    caseSensitive: false,
    multiLine: true,
  );

  static List<String> extract(String rawText) {
    final links = railwayLink
        .allMatches(rawText)
        .map((match) => match.group(0)!)
        .map((link) => link.replaceFirst(RegExp(r'[),.;!?]+$'), ''))
        .toList(growable: false);
    return links;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startProcessing() {
    final links = LinkExtractor.extract(_textController.text);
    if (links.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid Okala session links were found.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProcessingScreen(links: links),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const _AmbientGlow(alignment: Alignment.topRight),
            const _AmbientGlow(alignment: Alignment.bottomLeft, scale: 0.7),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 42),
                  const Text(
                    'Bulk session manager',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Paste your raw text below. Nexus Link will identify every session endpoint and connect them in sequence.',
                    style: TextStyle(
                      color: NexusColors.muted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Expanded(
                    child: _GlassPanel(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        cursorColor: NexusColors.green,
                        decoration: const InputDecoration(
                          hintText:
                              'Paste Okala session links or raw response text here...',
                          hintStyle: TextStyle(
                            color: Color(0x668C9AB8),
                            height: 1.5,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _GlowButton(
                    label: 'Start Processing',
                    icon: Icons.bolt_rounded,
                    onPressed: _startProcessing,
                  ),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'ساخته شده توسط @OkalaLink',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: NexusColors.muted,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
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

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({required this.links, super.key});

  final List<String> links;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  InAppWebViewController? _webViewController;
  int _currentIndex = 0;
  String _status = 'Starting high-speed processing...';
  String? _error;
  double _progress = 0.0;
  bool _isReady = false;

  late List<Map<String, dynamic>?> _accountPayloads;

  @override
  void initState() {
    super.initState();
    _accountPayloads = List.filled(widget.links.length, null);
  }

  void _startBulkProcessing() async {
    for (int i = 0; i < widget.links.length; i++) {
      if (!mounted) return;
      setState(() {
        _progress = (i + 1) / widget.links.length;
        _status = 'Fetching account data ${i + 1} / ${widget.links.length}...';
      });

      try {
        final response = await http.get(Uri.parse(widget.links[i])).timeout(const Duration(seconds: 10));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final payload = jsonDecode(response.body);
          if (payload is Map<String, dynamic>) {
            _accountPayloads[i] = payload;
          }
        }
      } catch (e) {
        // نادیده گرفتن خطا برای ادامه پردازش سایر اکانت‌ها
      }
    }

    if (!mounted) return;
    setState(() {
      _isReady = true;
      _progress = 1.0;
      _status = 'All accounts processed! Ready to view.';
    });

    _loadAccountToWebView(0);
  }

  Future<void> _loadAccountToWebView(int index) async {
    final payload = _accountPayloads[index];
    
    setState(() {
      _currentIndex = index;
      _error = null;
    });

    if (payload == null) {
      setState(() => _error = 'Failed to fetch data for this account.');
      return;
    }

    setState(() => _status = 'Connecting to Account ${index + 1}...');

    final target = 'https://www.okala.com/';
    final cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();

    final cookies = _readCookies(payload['cookies']);
    for (final cookie in cookies) {
      final name = cookie['name']?.toString();
      final value = cookie['value']?.toString();
      if (name == null || value == null || name.isEmpty) continue;
      await cookieManager.setCookie(
        url: WebUri(target),
        name: name,
        value: value,
        domain: '.okala.com',
        path: cookie['path']?.toString() ?? '/',
        isSecure: cookie['secure'] is bool ? cookie['secure'] as bool : true,
        isHttpOnly: cookie['httpOnly'] is bool ? cookie['httpOnly'] as bool : false,
      );
    }

    await _webViewController?.removeAllUserScripts();
    
    final localStorage = _readLocalStorage(payload['local_storage']);
    if (localStorage.isNotEmpty) {
      final script = localStorage.entries
          .map((entry) {
            final key = jsonEncode(entry.key);
            final value = jsonEncode(entry.value.toString());
            return "window.localStorage.setItem($key, $value);";
          })
          .join();
          
      await _webViewController?.addUserScript(
        userScript: UserScript(
          source: script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        )
      );
    }

    await _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target)),
    );

    setState(() => _status = 'Account ${index + 1} Connected ✓');
  }

  List<Map<String, dynamic>> _readCookies(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
    if (raw is Map) {
      return raw.entries
          .map((entry) => <String, dynamic>{
                'name': entry.key,
                'value': entry.value,
              })
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _readLocalStorage(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  Future<void> _reset() async {
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    await _webViewController?.clearCache();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nexus Link', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: NexusColors.navy.withValues(alpha: 0.92),
        actions: [
          if (_isReady) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: _currentIndex > 0 ? () => _loadAccountToWebView(_currentIndex - 1) : null,
              color: _currentIndex > 0 ? NexusColors.teal : NexusColors.muted,
              tooltip: 'Previous Account',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  '${_currentIndex + 1}/${widget.links.length}',
                  style: const TextStyle(color: NexusColors.teal, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
              onPressed: _currentIndex < widget.links.length - 1 ? () => _loadAccountToWebView(_currentIndex + 1) : null,
              color: _currentIndex < widget.links.length - 1 ? NexusColors.teal : NexusColors.muted,
              tooltip: 'Next Account',
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Clear all sessions',
            onPressed: _reset,
            icon: const Icon(Icons.delete_sweep_rounded, color: NexusColors.green),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            color: NexusColors.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_status, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _progress.clamp(0.0, 1.0).toDouble(),
                  backgroundColor: NexusColors.border,
                  color: NexusColors.green,
                  minHeight: 4,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  TextButton(onPressed: () => _loadAccountToWebView(_currentIndex), child: const Text('Try again')),
                ],
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                cacheEnabled: true,
                transparentBackground: true,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                _startBulkProcessing();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: NexusColors.teal.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NexusColors.teal.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: NexusColors.teal.withValues(alpha: 0.2), blurRadius: 18),
            ],
          ),
          child: const Icon(Icons.hub_rounded, color: NexusColors.teal, size: 25),
        ),
        const SizedBox(width: 12),
        const Text(
          'NEXUS LINK',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NexusColors.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: NexusColors.teal.withValues(alpha: 0.28), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: NexusColors.navy),
        label: Text(label, style: const TextStyle(color: NexusColors.navy, fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: NexusColors.teal,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.alignment, this.scale = 1});

  final Alignment alignment;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [NexusColors.teal.withValues(alpha: 0.1), Colors.transparent],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

