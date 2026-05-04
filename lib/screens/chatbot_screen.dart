import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../config/app_env.dart';
import '../services/api_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CROPEYE CHATBOT SCREEN
//  Connects to FastAPI /api/v1/chat endpoint
//  Supports English, Hindi, Marathi, Kannada
// ═══════════════════════════════════════════════════════════════════════════

class ChatbotScreen extends StatefulWidget {
  final FieldModel field;
  final String sessionId;

  const ChatbotScreen({
    super.key,
    required this.field,
    required this.sessionId,
  });

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen>
    with SingleTickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isLoading = false;
  late AnimationController _typingCtrl;

  // FastAPI chatbot base URL — add CHATBOT_URL to .env
  String get _chatbotUrl => AppEnv.chatbotUrl;

  @override
  void initState() {
    super.initState();
    _typingCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    // Welcome message
    _messages.add(_ChatMessage(
      text: '🌾 नमस्ते! I\'m your CropEye Assistant.\n\n'
          'I can help you with:\n'
          '• Field water & irrigation analysis\n'
          '• Crop health & NDVI data\n'
          '• Soil nutrients & fertilizer advice\n'
          '• Pest risk & weather info\n'
          '• How to use any feature in the app\n\n'
          'Ask me anything in English, Hindi, Marathi or Kannada! 🙏',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _typingCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(
        text: text.trim(),
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final body = jsonEncode({
        'session_id': widget.sessionId,
        'message':    text.trim(),
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

      final resp = await http.post(
        Uri.parse('$_chatbotUrl/api/v1/chat/message'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 45));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = data['reply'] as String?
            ?? data['message'] as String?
            ?? 'Sorry, could not get a response.';
        final sources = (data['data_sources_used'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [];

        setState(() {
          _isLoading = false;
          _messages.add(_ChatMessage(
            text: reply,
            isUser: false,
            timestamp: DateTime.now(),
            dataSources: sources,
          ));
        });
      } else {
        _addErrorMessage();
      }
    } catch (e) {
      _addErrorMessage();
    }
    _scrollToBottom();
  }

  void _addErrorMessage() {
    setState(() {
      _isLoading = false;
      _messages.add(_ChatMessage(
        text: 'Sorry, I could not connect to the server. Please check your internet and try again.',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
      ));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Quick action chips
  final List<Map<String, String>> _quickActions = [
    {'label': '💧 Water Status', 'msg': 'What is the water status of my field?'},
    {'label': '🌱 Crop Health', 'msg': 'How healthy are my crops?'},
    {'label': '🪲 Pest Risk',   'msg': 'Is there any pest risk in my field?'},
    {'label': '🌾 Fertilizer',  'msg': 'Do I need to apply fertilizer?'},
    {'label': '☁️ Weather',     'msg': 'What is the current weather at my field?'},
    {'label': '📱 How to use',  'msg': 'How do I use the NDVI feature?'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: SafeArea(
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.18),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                ),
                child: const Text('🌾',
                    style: TextStyle(fontSize: 22),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CropEye Assistant',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(widget.field.name,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              )),
              // Online indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF76FF03).withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF76FF03).withOpacity(0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, color: Color(0xFF76FF03), size: 7),
                  SizedBox(width: 4),
                  Text('Live', style: TextStyle(color: Color(0xFF76FF03),
                      fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ),

          // ── Messages ──────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length && _isLoading) {
                  return _TypingIndicator(ctrl: _typingCtrl);
                }
                return _MessageBubble(message: _messages[i]);
              },
            ),
          ),

          // ── Quick action chips ────────────────────────────────────────
          if (_messages.length <= 2)
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _quickActions.length,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => _sendMessage(_quickActions[i]['msg']!),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Text(_quickActions[i]['label']!,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ),
              ),
            ),

          // ── Input bar ─────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08),
                    blurRadius: 12, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14,
                      color: AppColors.textDark),
                  decoration: const InputDecoration(
                    hintText:
                        'Ask in English, हिंदी, मराठी or ಕನ್ನಡ...',
                    hintStyle: TextStyle(
                        color: AppColors.textLight, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (v) => _sendMessage(v),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _sendMessage(_inputCtrl.text),
                child: Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}


// ── Message data model ─────────────────────────────────────────────────────
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String> dataSources;
  final bool isError;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.dataSources = const [],
    this.isError = false,
  });
}


// ── Message bubble widget ──────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.12),
              ),
              child: const Text('🌾',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.primary
                    : (message.isError
                        ? const Color(0xFFFFEBEE)
                        : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isUser
                          ? Colors.white
                          : (message.isError
                              ? Colors.red.shade700
                              : AppColors.textDark),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (message.dataSources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: message.dataSources.map((s) =>
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('📡 $s',
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }
}


// ── Typing indicator ───────────────────────────────────────────────────────
class _TypingIndicator extends StatelessWidget {
  final AnimationController ctrl;
  const _TypingIndicator({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withOpacity(0.12),
          ),
          child: const Text('🌾',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 6)
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(ctrl: ctrl, delay: 0),
            const SizedBox(width: 4),
            _Dot(ctrl: ctrl, delay: 0.33),
            const SizedBox(width: 4),
            _Dot(ctrl: ctrl, delay: 0.66),
          ]),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  final AnimationController ctrl;
  final double delay;
  const _Dot({required this.ctrl, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ((ctrl.value - delay) % 1.0).abs();
        final scale = 0.7 + t * 0.6;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.6),
            ),
          ),
        );
      },
    );
  }
}
