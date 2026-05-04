import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/app_env.dart';
import '../constants/app_constants.dart';
import 'alert_feed_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AI RECOMMENDATION CENTRE
//
//  A unified panel combining:
//    Tab 1 — ALERTS:  All actionable alerts with AI recommendations
//                     fetched from the chatbot API per alert
//    Tab 2 — AI CHAT: Full chatbot session for the current field
//    Tab 3 — VISION:  Camera + Gemini Vision analysis
//
//  The chatbot backend (FastAPI + Groq + LangGraph) powers Tabs 1 & 2.
//  Gemini Vision API powers Tab 3.
// ═══════════════════════════════════════════════════════════════════════════

class AiRecommendationCentre extends StatefulWidget {
  final FieldModel           field;
  final List<ActionableAlert> alerts;
  final VoidCallback          onClose;

  const AiRecommendationCentre({
    super.key,
    required this.field,
    required this.alerts,
    required this.onClose,
  });

  @override
  State<AiRecommendationCentre> createState() => _AiRecommendationCentreState();
}

class _AiRecommendationCentreState extends State<AiRecommendationCentre>
    with TickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────
          _Header(field: widget.field, onClose: widget.onClose),

          // ── Tab bar ─────────────────────────────────────────────
          Container(
            color: const Color(0xFF0D1428),
            child: TabBar(
              controller: _tabs,
              indicatorColor: const Color(0xFF7B1FA2),
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900,
                  letterSpacing: 0.8),
              unselectedLabelColor: Colors.white30,
              labelColor: const Color(0xFFCE93D8),
              tabs: [
                Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Icon(Icons.warning_amber_rounded, size: 14),
                    const SizedBox(width: 5),
                    Text('ALERTS${widget.alerts.isNotEmpty
                        ? " (${widget.alerts.length})" : ""}'),
                  ]),
                ),
                const Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.smart_toy_outlined, size: 14),
                    SizedBox(width: 5),
                    Text('AI CHAT'),
                  ]),
                ),
                const Tab(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.remove_red_eye_outlined, size: 14),
                    SizedBox(width: 5),
                    Text('VISION'),
                  ]),
                ),
              ],
            ),
          ),

          // ── Tab views ────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _AlertsTab(
                    field: widget.field, alerts: widget.alerts),
                _ChatTab(field: widget.field),
                _VisionTab(field: widget.field),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Shared header ──────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final FieldModel   field;
  final VoidCallback onClose;
  const _Header({required this.field, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1428),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF7B1FA2).withOpacity(0.3)),
        ),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 15),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.auto_awesome_rounded,
            color: Color(0xFFCE93D8), size: 20),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AI Recommendation Centre',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 0.2)),
          Text(field.name,
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF7B1FA2).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF7B1FA2).withOpacity(0.4)),
          ),
          child: Text(field.crop,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                  color: Color(0xFFCE93D8))),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 1 — ALERTS  with AI recommendations per alert
// ═══════════════════════════════════════════════════════════════════════════
class _AlertsTab extends StatefulWidget {
  final FieldModel           field;
  final List<ActionableAlert> alerts;
  const _AlertsTab({required this.field, required this.alerts});

  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  // Recommendation text per alert id — fetched from chatbot API
  final Map<String, String> _recs   = {};
  final Map<String, bool>   _loading = {};

  Future<void> _fetchRec(ActionableAlert alert) async {
    if (_recs.containsKey(alert.id) || _loading[alert.id] == true) return;
    setState(() => _loading[alert.id] = true);

    final question =
        'Give a 2–3 sentence practical recommendation for this alert: '
        '"${alert.title} — ${alert.message}" '
        'For ${widget.field.crop} crop in field "${widget.field.name}". '
        'Be specific and actionable. No headings.';

    try {
      final reply = await _callChatbot(question);
      if (mounted) setState(() { _recs[alert.id] = reply; _loading[alert.id] = false; });
    } catch (_) {
      if (mounted) setState(() {
        _recs[alert.id] = 'Could not fetch recommendation. Check CHATBOT_URL in .env';
        _loading[alert.id] = false;
      });
    }
  }

  Future<String> _callChatbot(String msg) async {
    final url  = Uri.parse('${AppEnv.chatbotUrl}/api/v1/chat/message');
    final body = jsonEncode({
      'session_id': 'rec_${widget.field.id}',
      'message':    msg,
      'plot_id':    widget.field.plotNameForAnalysis,
      'language':   'en',
      'context': {
        'crop':            widget.field.crop,
        'plantation_date': widget.field.plantationDate ?? '',
        'field_name':      widget.field.name,
        'lat':             widget.field.center[0],
        'lon':             widget.field.center[1],
      },
    });
    final r = await http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 25));
    if (r.statusCode == 200) {
      final d = jsonDecode(r.body);
      return (d['reply'] as String? ?? d['message'] as String? ?? '').trim();
    }
    throw Exception('${r.statusCode}');
  }

  Color _sevColor(String s) {
    switch (s) {
      case 'critical': return const Color(0xFFB71C1C);
      case 'high':     return const Color(0xFFE53935);
      case 'medium':   return const Color(0xFFF57C00);
      default:         return const Color(0xFF2E7D32);
    }
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'pest':    return Icons.bug_report_rounded;
      case 'water':   return Icons.water_drop_rounded;
      case 'soil':    return Icons.terrain_rounded;
      case 'growth':  return Icons.eco_rounded;
      case 'weather': return Icons.wb_cloudy_rounded;
      case 'harvest': return Icons.grass_rounded;
      default:        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alerts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('✅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('No Active Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 6),
          Text('Your ${widget.field.name} field looks healthy.',
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: widget.alerts.length,
      itemBuilder: (_, i) {
        final a      = widget.alerts[i];
        final sColor = _sevColor(a.severity);
        final rec    = _recs[a.id];
        final isLoading = _loading[a.id] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1628),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sColor.withOpacity(0.30)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // ── Alert header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: sColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: sColor.withOpacity(0.4)),
                  ),
                  child: Icon(_typeIcon(a.type), color: sColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(a.title,
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(a.timeAgo,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sColor.withOpacity(0.5)),
                  ),
                  child: Text(a.severity.toUpperCase(),
                      style: TextStyle(fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: sColor, letterSpacing: 0.8)),
                ),
              ]),
            ),

            // ── Alert message ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(a.message,
                  style: TextStyle(fontSize: 12,
                      color: Colors.white.withOpacity(0.72), height: 1.45)),
            ),

            const Divider(color: Colors.white10, height: 1),

            // ── AI Recommendation area ────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 13, color: Color(0xFFCE93D8)),
                  const SizedBox(width: 5),
                  const Text('AI Recommendation',
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFCE93D8), letterSpacing: 0.5)),
                  const Spacer(),
                  if (rec == null && !isLoading)
                    GestureDetector(
                      onTap: () => _fetchRec(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B1FA2).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF7B1FA2).withOpacity(0.4)),
                        ),
                        child: const Text('Get Advice',
                            style: TextStyle(fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFCE93D8))),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                if (isLoading)
                  const Row(children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFCE93D8))),
                    SizedBox(width: 10),
                    Text('Asking AI...',
                        style: TextStyle(fontSize: 11,
                            color: Colors.white38)),
                  ])
                else if (rec != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF7B1FA2).withOpacity(0.2)),
                    ),
                    child: Text(rec,
                        style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                            height: 1.5)),
                  )
                else
                  Text('Tap "Get Advice" for AI recommendation',
                      style: TextStyle(fontSize: 11,
                          color: Colors.white.withOpacity(0.25),
                          fontStyle: FontStyle.italic)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 2 — AI CHAT  (FastAPI chatbot)
// ═══════════════════════════════════════════════════════════════════════════
class _ChatTab extends StatefulWidget {
  final FieldModel field;
  const _ChatTab({required this.field});
  @override State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final List<_ChatMsg>      _msgs    = [];
  final TextEditingController _ctrl  = TextEditingController();
  final ScrollController    _scroll  = ScrollController();
  final stt.SpeechToText    _speech  = stt.SpeechToText();
  bool _loading   = false;
  bool _listening = false;

  static const _suggestions = [
    'What should I do about pest risk?',
    'When should I irrigate?',
    'Is my crop ready to harvest?',
    'What fertilizer should I apply?',
  ];

  @override
  void initState() {
    super.initState();
    _speech.initialize();
    _addMsg('🌾 नमस्ते! I\'m your CropEye field assistant.\n'
        'Ask me anything about ${widget.field.name} '
        '(${widget.field.crop}) in English, Hindi, Marathi or Kannada.',
        isUser: false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addMsg(String text, {required bool isUser}) {
    setState(() => _msgs.add(_ChatMsg(text: text, isUser: isUser)));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String msg) async {
    if (msg.trim().isEmpty) return;
    _ctrl.clear();
    _addMsg(msg, isUser: true);
    setState(() => _loading = true);

    try {
      final url  = Uri.parse('${AppEnv.chatbotUrl}/api/v1/chat/message');
      final body = jsonEncode({
        'session_id': 'rec_chat_${widget.field.id}',
        'message':    msg,
        'plot_id':    widget.field.plotNameForAnalysis,
        'language':   'en',
        'context': {
          'crop':            widget.field.crop,
          'plantation_date': widget.field.plantationDate ?? '',
          'field_name':      widget.field.name,
          'lat':             widget.field.center[0],
          'lon':             widget.field.center[1],
        },
      });
      final r = await http.post(url,
          headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));
      final reply = r.statusCode == 200
          ? (jsonDecode(r.body)['reply'] as String?
              ?? jsonDecode(r.body)['message'] as String?
              ?? 'No response')
          : '⚠️ Error ${r.statusCode}. Check CHATBOT_URL in .env';
      _addMsg(reply, isUser: false);
    } catch (e) {
      _addMsg('⚠️ Could not reach chatbot. Check CHATBOT_URL in .env', isUser: false);
    }
    setState(() => _loading = false);
  }

  void _toggleListen() async {
    if (_listening) {
      _speech.stop();
      setState(() => _listening = false);
    } else {
      setState(() => _listening = true);
      await _speech.listen(onResult: (r) {
        if (r.finalResult && r.recognizedWords.isNotEmpty) {
          _speech.stop();
          setState(() => _listening = false);
          _send(r.recognizedWords);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Messages
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          itemCount: _msgs.length + (_loading ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == _msgs.length) {
              // Typing indicator
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF7B1FA2).withOpacity(0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFCE93D8))),
                      const SizedBox(width: 8),
                      Text('Thinking...',
                          style: TextStyle(fontSize: 11,
                              color: Colors.white.withOpacity(0.5))),
                    ]),
                  ),
                ),
              );
            }
            final m = _msgs[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: m.isUser
                    ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: m.isUser
                        ? Colors.white.withOpacity(0.07)
                        : const Color(0xFF7B1FA2).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: m.isUser
                          ? Colors.white10
                          : const Color(0xFF7B1FA2).withOpacity(0.25),
                    ),
                  ),
                  child: Text(m.text,
                      style: TextStyle(fontSize: 13,
                          color: Colors.white.withOpacity(0.88),
                          height: 1.45)),
                ),
              ),
            );
          },
        ),
      ),

      // Suggestion chips (shown when < 3 messages)
      if (_msgs.length < 3)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: _suggestions.map((s) => GestureDetector(
              onTap: () => _send(s),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(s,
                    style: const TextStyle(fontSize: 11,
                        color: Colors.white60)),
              ),
            )).toList(),
          ),
        ),

      // Input bar
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1428),
          border: Border(
              top: BorderSide(
                  color: const Color(0xFF7B1FA2).withOpacity(0.2))),
        ),
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Ask anything about your field...',
                  hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
                onSubmitted: _send,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic
          GestureDetector(
            onTap: _toggleListen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _listening
                    ? Colors.red.withOpacity(0.8)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _listening ? Colors.red : Colors.white10),
              ),
              child: Icon(_listening ? Icons.mic_off : Icons.mic,
                  color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          // Send
          GestureDetector(
            onTap: _loading ? null : () => _send(_ctrl.text),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _ChatMsg {
  final String text;
  final bool   isUser;
  const _ChatMsg({required this.text, required this.isUser});
}

// ═══════════════════════════════════════════════════════════════════════════
//  TAB 3 — VISION  (Camera + Gemini Vision)
// ═══════════════════════════════════════════════════════════════════════════
class _VisionTab extends StatefulWidget {
  final FieldModel field;
  const _VisionTab({required this.field});
  @override State<_VisionTab> createState() => _VisionTabState();
}

class _VisionTabState extends State<_VisionTab> {
  CameraController? _cam;
  bool _camReady  = false;
  bool _processing = false;

  final List<_VisionResult> _results = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _cam = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      debugPrint('Camera: $e');
    }
  }

  Future<void> _analyse() async {
    if (_processing || !_camReady) return;
    setState(() => _processing = true);

    try {
      final xfile = await _cam!.takePicture();
      final bytes = await xfile.readAsBytes();
      final b64   = base64Encode(bytes);

      final prompt =
          'You are an agricultural AI. Analyse this farm/field image carefully.\n'
          'Field: ${widget.field.name} | Crop: ${widget.field.crop}\n'
          'Identify:\n'
          '1. Any visible crop stress, yellowing, or disease symptoms\n'
          '2. Pest damage signs (holes, webbing, discolouration)\n'
          '3. Water stress indicators (wilting, dry soil)\n'
          '4. Growth stage assessment\n'
          '5. Immediate action recommended\n'
          'Be concise and practical. Use bullet points.';

      final apiKey = AppEnv.geminiApiKey;
      if (apiKey.isEmpty) {
        setState(() {
          _results.insert(0, _VisionResult(
            analysis: '⚠️ Add GEMINI_API_KEY to .env to use Vision AI',
            timestamp: DateTime.now(),
          ));
          _processing = false;
        });
        return;
      }

      final url = 'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-2.0-flash:generateContent?key=$apiKey';

      final r = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'text': prompt},
              {'inline_data': {'mime_type': 'image/jpeg', 'data': b64}}
            ]
          }],
          'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 600},
        }),
      ).timeout(const Duration(seconds: 30));

      String analysis;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        analysis = d['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String? ?? 'No analysis returned.';
      } else {
        analysis = '⚠️ Gemini error ${r.statusCode}';
      }

      if (mounted) {
        setState(() {
          _results.insert(0, _VisionResult(
            analysis: analysis,
            timestamp: DateTime.now(),
            imageBytes: bytes,
          ));
          _processing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results.insert(0, _VisionResult(
            analysis: '⚠️ Error: $e',
            timestamp: DateTime.now(),
          ));
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Camera preview
      Container(
        height: 220,
        margin: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1F14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF7B1FA2).withOpacity(0.3)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(children: [
            if (_camReady && _cam != null)
              Positioned.fill(child: CameraPreview(_cam!))
            else
              const Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.camera_alt_outlined,
                      color: Colors.white24, size: 36),
                  SizedBox(height: 8),
                  Text('Initialising camera...',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),

            if (_processing)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const CircularProgressIndicator(
                          color: Color(0xFFCE93D8)),
                      const SizedBox(height: 12),
                      Text('Gemini Vision analysing...',
                          style: TextStyle(color: Colors.white.withOpacity(0.7),
                              fontSize: 12)),
                    ]),
                  ),
                ),
              ),

            // Analyse button
            Positioned(
              bottom: 12, right: 12,
              child: GestureDetector(
                onTap: _processing ? null : _analyse,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF7B1FA2).withOpacity(0.4),
                          blurRadius: 10),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    const Text('Analyse',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),

      // Results list
      Expanded(
        child: _results.isEmpty
            ? Center(
                child: Text('Point camera at your field and tap Analyse',
                    style: TextStyle(fontSize: 12,
                        color: Colors.white.withOpacity(0.3)),
                    textAlign: TextAlign.center),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1628),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF7B1FA2).withOpacity(0.2)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        const Icon(Icons.remove_red_eye_outlined,
                            size: 13, color: Color(0xFFCE93D8)),
                        const SizedBox(width: 5),
                        const Text('Vision Analysis',
                            style: TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFCE93D8))),
                        const Spacer(),
                        Text(
                          '${r.timestamp.hour.toString().padLeft(2,'0')}:'
                          '${r.timestamp.minute.toString().padLeft(2,'0')}',
                          style: const TextStyle(fontSize: 9,
                              color: Colors.white30),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(r.analysis,
                          style: TextStyle(fontSize: 12.5,
                              color: Colors.white.withOpacity(0.82),
                              height: 1.5)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

class _VisionResult {
  final String    analysis;
  final DateTime  timestamp;
  final Uint8List? imageBytes;
  const _VisionResult({
    required this.analysis,
    required this.timestamp,
    this.imageBytes,
  });
}
