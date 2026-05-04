import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/app_env.dart';
import '../constants/app_constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SCREEN SHARE PANEL  —  Flutter-native equivalent of the React web app
//
//  Features:
//    • Live camera preview (front or back) — simulates "screen sharing"
//      by capturing the phone camera view of the farm
//    • Capture frame → send to Gemini Vision API → AI analysis
//    • Auto-explain mode: captures + analyses every 8 seconds
//    • Voice input (speech_to_text) — ask questions verbally
//    • Language switcher: English / Hindi / Marathi / Kannada
//    • Chat history with animated messages
//    • CropEye-branded dark UI matching the React app aesthetic
// ═══════════════════════════════════════════════════════════════════════════

class ScreenSharePanel extends StatefulWidget {
  final FieldModel field;
  final VoidCallback onClose;

  const ScreenSharePanel({
    super.key,
    required this.field,
    required this.onClose,
  });

  @override
  State<ScreenSharePanel> createState() => _ScreenSharePanelState();
}

class _ScreenSharePanelState extends State<ScreenSharePanel>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _camReady  = false;
  bool _useFront  = false;

  // ── Chat ────────────────────────────────────────────────────────
  final List<_Msg> _messages = [];
  final ScrollController _scroll = ScrollController();
  bool _processing = false;

  // ── Auto-explain ────────────────────────────────────────────────
  bool _autoExplain = false;
  Timer? _autoTimer;

  // ── Voice ────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening       = false;

  // ── Language ─────────────────────────────────────────────────────
  int _langIdx = 0;
  static const _langs = [
    ('en-IN', 'English'),
    ('hi-IN', 'Hindi'),
    ('mr-IN', 'Marathi'),
    ('kn-IN', 'Kannada'),
  ];

  // ── Animations ────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initCamera();
    _initSpeech();

    // Welcome message
    _addMsg('🌾 CropEye Vision is ready.\n\n'
        'Point your camera at your field and tap **Analyse** for instant AI insights.\n'
        'Or turn on **Auto-Explain** for continuous monitoring.\n\n'
        'You can also speak your question in English, Hindi, Marathi or Kannada.',
        isUser: false);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _autoTimer?.cancel();
    _camCtrl?.dispose();
    super.dispose();
  }

  // ── Camera init ─────────────────────────────────────────────────
  Future<void> _initCamera({bool front = false}) async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == (front
            ? CameraLensDirection.front
            : CameraLensDirection.back),
        orElse: () => cams.first,
      );
      await _camCtrl?.dispose();
      _camCtrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await _camCtrl!.initialize();
      if (mounted) setState(() { _camReady = true; _useFront = front; });
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  Future<void> _flipCamera() async {
    setState(() => _camReady = false);
    await _initCamera(front: !_useFront);
  }

  // ── Speech init ──────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  void _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
    } else if (_speechAvailable) {
      setState(() => _listening = true);
      await _speech.listen(
        localeId: _langs[_langIdx].$1,
        onResult: (r) {
          if (r.finalResult && r.recognizedWords.isNotEmpty) {
            _speech.stop();
            setState(() => _listening = false);
            _analyseWithQuestion(r.recognizedWords);
          }
        },
      );
    }
  }

  // ── Auto-explain toggle ──────────────────────────────────────────
  void _toggleAutoExplain() {
    setState(() => _autoExplain = !_autoExplain);
    if (_autoExplain) {
      _analyseFrame();
      _autoTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!_processing) _analyseFrame();
      });
    } else {
      _autoTimer?.cancel();
    }
  }

  // ── Capture frame → base64 ────────────────────────────────────────
  Future<String?> _captureFrame() async {
    if (_camCtrl == null || !_camReady) return null;
    try {
      final xfile = await _camCtrl!.takePicture();
      final bytes = await xfile.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      return null;
    }
  }

  // ── Analyse current frame ─────────────────────────────────────────
  Future<void> _analyseFrame({String? extraQuestion}) async {
    if (_processing) return;
    setState(() => _processing = true);

    final frame = await _captureFrame();
    if (frame == null) {
      setState(() => _processing = false);
      return;
    }

    final question = extraQuestion ??
        'Analyse this farm/field view. Identify any visible crop stress, '
        'pest damage, water issues, or growth anomalies. '
        'Give a concise actionable insight for the farmer. '
        'Field: ${widget.field.name}, Crop: ${widget.field.crop}. '
        'Respond in ${_langs[_langIdx].$2}.';

    if (extraQuestion != null) {
      _addMsg(extraQuestion, isUser: true);
    }

    try {
      final response = await _callGeminiVision(frame, question);
      _addMsg(response, isUser: false);
    } catch (e) {
      _addMsg('⚠️ Could not analyse image. Check your Gemini API key in .env', isUser: false);
    }

    setState(() => _processing = false);
  }

  Future<void> _analyseWithQuestion(String question) async {
    _addMsg(question, isUser: true);
    if (_processing) return;
    setState(() => _processing = true);

    final frame = await _captureFrame();

    String prompt;
    if (frame != null) {
      prompt = 'The farmer is looking at this field view and asks: "$question"\n'
          'Field: ${widget.field.name}, Crop: ${widget.field.crop}.\n'
          'Respond in ${_langs[_langIdx].$2} concisely and practically.';
    } else {
      prompt = 'A farmer with ${widget.field.crop} in ${widget.field.name} asks: "$question"\n'
          'Respond in ${_langs[_langIdx].$2} concisely and practically.';
    }

    try {
      final response = frame != null
          ? await _callGeminiVision(frame, prompt)
          : await _callGeminiText(prompt);
      _addMsg(response, isUser: false);
    } catch (e) {
      _addMsg('⚠️ Could not get response. Check your internet connection.', isUser: false);
    }

    setState(() => _processing = false);
  }

  // ── Gemini Vision API call ────────────────────────────────────────
  Future<String> _callGeminiVision(String base64Image, String prompt) async {
    final apiKey = AppEnv.geminiApiKey;
    if (apiKey.isEmpty) {
      return '⚠️ Gemini API key not set. Add GEMINI_API_KEY to your .env file.';
    }

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=$apiKey';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 512,
      }
    });

    final r = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 30));

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String? ?? 'No response from Gemini.';
    }
    throw Exception('Gemini error ${r.statusCode}: ${r.body}');
  }

  // ── Gemini Text API call (no image) ──────────────────────────────
  Future<String> _callGeminiText(String prompt) async {
    final apiKey = AppEnv.geminiApiKey;
    if (apiKey.isEmpty) return '⚠️ Gemini API key not set.';

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=$apiKey';

    final r = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': [{'text': prompt}]}],
        'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 512},
      }),
    ).timeout(const Duration(seconds: 20));

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String? ?? 'No response.';
    }
    throw Exception('${r.statusCode}');
  }

  // ── Add message + scroll ─────────────────────────────────────────
  void _addMsg(String text, {required bool isUser}) {
    setState(() => _messages.add(_Msg(text: text, isUser: isUser)));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final (langCode, langName) = _langs[_langIdx];

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────
          _buildHeader(langName),

          // ── Body: Camera + Chat ──────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Camera preview
                Expanded(
                  flex: 5,
                  child: _buildCameraPanel(),
                ),
                // Right: Chat
                Expanded(
                  flex: 4,
                  child: _buildChatPanel(),
                ),
              ],
            ),
          ),

          // ── Bottom controls ──────────────────────────────────────
          _buildBottomBar(),
        ]),
      ),
    );
  }

  Widget _buildHeader(String langName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF00BCD4).withOpacity(0.3)),
        ),
      ),
      child: Row(children: [
        // Back
        GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        // Title
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CropEye Vision',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 0.3)),
          Text('Field AI · ${widget.field.name}',
              style: TextStyle(fontSize: 10,
                  color: Colors.white.withOpacity(0.45))),
        ]),
        const Spacer(),
        // Live indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF00BCD4).withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00BCD4)
                      .withOpacity(_pulse.value),
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Text('LIVE', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w900,
                color: Color(0xFF00BCD4), letterSpacing: 1.2)),
          ]),
        ),
        const SizedBox(width: 8),
        // Language switcher
        GestureDetector(
          onTap: () => setState(() => _langIdx = (_langIdx + 1) % _langs.length),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(langName,
                style: const TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700, color: Colors.white70)),
          ),
        ),
      ]),
    );
  }

  Widget _buildCameraPanel() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        // Camera view
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1F14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF00BCD4).withOpacity(0.2)),
              ),
              child: Stack(children: [
                // Camera preview
                if (_camReady && _camCtrl != null)
                  Positioned.fill(child: CameraPreview(_camCtrl!))
                else
                  Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.camera_alt_outlined,
                          color: Colors.white24, size: 40),
                      const SizedBox(height: 10),
                      const Text('Initialising camera...',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                  ),

                // Processing overlay
                if (_processing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF00BCD4).withOpacity(0.4)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF00BCD4)),
                            ),
                            const SizedBox(width: 10),
                            const Text('Analysing...',
                                style: TextStyle(color: Colors.white70,
                                    fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                  ),

                // Flip button
                Positioned(
                  top: 8, right: 8,
                  child: GestureDetector(
                    onTap: _flipCamera,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.flip_camera_android,
                          color: Colors.white70, size: 16),
                    ),
                  ),
                ),

                // Auto-explain badge
                if (_autoExplain)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF00BCD4).withOpacity(0.5)),
                      ),
                      child: const Text('AUTO',
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00BCD4), letterSpacing: 1)),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Auto-explain + Analyse buttons
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _toggleAutoExplain,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _autoExplain
                      ? const Color(0xFF00BCD4).withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _autoExplain
                          ? const Color(0xFF00BCD4).withOpacity(0.5)
                          : Colors.white12),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _autoExplain
                          ? const Color(0xFF00BCD4)
                          : Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_autoExplain ? 'Auto-Explain ON' : 'Auto-Explain',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _autoExplain
                              ? const Color(0xFF00BCD4)
                              : Colors.white38)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _processing ? null : _analyseFrame,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF006064), Color(0xFF00BCD4)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00BCD4).withOpacity(0.3),
                      blurRadius: 10),
                ],
              ),
              child: const Icon(Icons.arrow_forward,
                  color: Colors.white, size: 20),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildChatPanel() {
    return Column(children: [
      // Chat header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF00BCD4).withOpacity(0.08),
          border: Border(
              bottom: BorderSide(
                  color: const Color(0xFF00BCD4).withOpacity(0.2))),
        ),
        child: Row(children: [
          const Text('CropEye Expert',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  color: Color(0xFF00BCD4), letterSpacing: 0.5)),
          const Spacer(),
          const Text('Precision Agriculture AI',
              style: TextStyle(fontSize: 9, color: Colors.white38)),
        ]),
      ),

      // Messages
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(10),
          itemCount: _messages.length,
          itemBuilder: (_, i) {
            final m = _messages[i];
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment:
                    m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: m.isUser
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFF00BCD4).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: m.isUser
                          ? Colors.white12
                          : const Color(0xFF00BCD4).withOpacity(0.25),
                    ),
                  ),
                  child: Text(m.text,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withOpacity(0.85),
                          height: 1.45)),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border(
          top: BorderSide(color: const Color(0xFF00BCD4).withOpacity(0.2)),
        ),
      ),
      child: Row(children: [
        // Voice bars indicator
        if (_listening)
          Row(children: List.generate(6, (i) {
            return AnimatedContainer(
              duration: Duration(milliseconds: 200 + i * 60),
              width: 3,
              height: 8.0 + (i % 3) * 8,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }))
        else
          Text('Tap mic to ask in ${_langs[_langIdx].$2}',
              style: const TextStyle(fontSize: 10, color: Colors.white30)),

        const Spacer(),

        // Mic button
        GestureDetector(
          onTap: _speechAvailable ? _toggleListen : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _listening
                  ? Colors.red.withOpacity(0.85)
                  : const Color(0xFF006064),
              borderRadius: BorderRadius.circular(12),
              boxShadow: _listening
                  ? [BoxShadow(color: Colors.red.withOpacity(0.4),
                      blurRadius: 12)]
                  : [],
            ),
            child: Icon(
              _listening ? Icons.mic_off : Icons.mic,
              color: Colors.white, size: 20,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Msg {
  final String text;
  final bool   isUser;
  const _Msg({required this.text, required this.isUser});
}
