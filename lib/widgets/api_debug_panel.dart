import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

/// Long-press the FP avatar on dashboard to open this panel.
/// It lets you see exactly what the server returns for every API call.
class ApiDebugPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ApiDebugPanel({super.key, required this.onClose});

  @override
  State<ApiDebugPanel> createState() => _ApiDebugPanelState();
}

class _ApiDebugPanelState extends State<ApiDebugPanel> {
  final List<_LogEntry> _entries = [];
  bool _busy = false;

  void _log(String title, String body, {bool ok = true}) {
    setState(() => _entries.insert(0, _LogEntry(title, body, ok)));
  }

  Future<void> _dumpAuthResponse() async {
    final resp = ApiService.lastAuthResponse;
    if (resp.isEmpty) {
      _log('Auth Response', '⚠️ No auth response stored.\nLogin first.', ok: false);
      return;
    }
    final sb = StringBuffer();
    sb.writeln('farmerId → ${ApiService.farmerId}');
    sb.writeln('accessToken: ${ApiService.accessToken?.substring(0, 24)}...');
    sb.writeln('');
    sb.writeln('ALL KEYS:');
    void dump(Map m, String indent) {
      m.forEach((k, v) {
        if (v is Map) {
          sb.writeln('$indent"$k": {');
          dump(v, '$indent  ');
          sb.writeln('$indent}');
        } else {
          sb.writeln('$indent"$k": $v  (${v.runtimeType})');
        }
      });
    }
    dump(resp, '  ');
    _log('Auth Response Keys', sb.toString(), ok: ApiService.farmerId != null);
  }

  Future<void> _probeGetPlots() async {
    setState(() => _busy = true);
    try {
      final plots = await ApiService.getPlots();
      if (plots.isEmpty) {
        _log('GET Plots', '⚠️ 0 plots returned.\nfarmerId=${ApiService.farmerId}\nCheck device logs for which URL was tried.', ok: false);
      } else {
        final sb = StringBuffer('✅ ${plots.length} plots:\n\n');
        for (final p in plots) {
          sb.writeln('id=${p['id']}  name="${p['name']}"');
          sb.writeln('farmer=${p['farmer']}');
          sb.writeln('center=${p['center']}');
          final polyStr = jsonEncode(p['polygon']);
          sb.writeln('polygon(${polyStr.length}chars)=${polyStr.substring(0, polyStr.length.clamp(0, 80))}...');
          sb.writeln('');
        }
        _log('GET Plots', sb.toString());
      }
    } catch (e) {
      _log('GET Plots', '❌ $e', ok: false);
    }
    setState(() => _busy = false);
  }

  Future<void> _probeAddPlot() async {
    final fid = ApiService.farmerId;
    if (fid == null) {
      _log('Add Plot Test', '❌ farmerId is null.\nLogin or register first.', ok: false);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ApiService.addPlot(
        farmerId: fid,
        name:     'DEBUG_TEST_${DateTime.now().millisecond}',
        center:   [20.0144, 73.7393],
        polygon: [
          [20.0140, 73.7389], [20.0148, 73.7389],
          [20.0148, 73.7397], [20.0140, 73.7397],
        ],
      );
      _log('Add Plot Test',
          '✅ SUCCESS!\nEndpoint: ${result['_saved_endpoint']}\nVariant: ${result['_saved_variant']}\nFull: ${jsonEncode(result)}');
    } catch (e) {
      _log('Add Plot Test', '❌ $e', ok: false);
    }
    setState(() => _busy = false);
  }

  Future<void> _probeEndpointRaw(String method, String path) async {
    setState(() => _busy = true);
    final url = '${ApiService.baseUrl}$path';
    try {
      final hdrs = {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
        if (ApiService.accessToken != null)
          'Authorization': 'Bearer ${ApiService.accessToken}',
      };
      late http.Response r;
      if (method == 'GET') {
        r = await http.get(Uri.parse(url), headers: hdrs);
      } else {
        r = await http.head(Uri.parse(url), headers: hdrs);
      }
      _log('$method $path', '${r.statusCode}\n\n${r.body.length > 800 ? r.body.substring(0, 800) + '...' : r.body}',
          ok: r.statusCode < 400);
    } catch (e) {
      _log('$method $path', '❌ $e', ok: false);
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.3), width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)],
        ),
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade900.withOpacity(0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              const Icon(Icons.terminal, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'API Debug  •  farmer=${ApiService.farmerId ?? "null"}  '
                  '${ApiService.accessToken != null ? "🔑" : "🔒"}',
                  style: const TextStyle(color: Colors.greenAccent,
                      fontWeight: FontWeight.w800, fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
              GestureDetector(
                onTap: widget.onClose,
                child: const Icon(Icons.close, color: Colors.white54, size: 20)),
            ]),
          ),

          // ── Action buttons ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              _btn('Auth Keys',   _dumpAuthResponse,         Colors.blue),
              _btn('Get Plots',   _probeGetPlots,            Colors.orange),
              _btn('Test Add',    _probeAddPlot,             Colors.green),
              _btn('GET /plots',  () => _probeEndpointRaw('GET', '/api/farmers/plots/'),   Colors.purple),
              _btn('GET /plot',   () => _probeEndpointRaw('GET', '/api/farmers/plot/'),    Colors.purple),
              _btn('GET /list',   () => _probeEndpointRaw('GET', '/api/farmers/plots/list/'), Colors.purple),
              _btn('Copy All', () {
                final all = _entries.map((e) => '=== ${e.title} ===\n${e.body}').join('\n\n');
                Clipboard.setData(ClipboardData(text: all));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')));
              }, Colors.grey.shade600),
              _btn('Clear',   () => setState(() => _entries.clear()), Colors.red.shade800),
            ]),
          ),

          // ── Log entries ──────────────────────────────────────────
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator(
                    color: Colors.greenAccent, strokeWidth: 2))
                : _entries.isEmpty
                    ? const Center(
                        child: Text('Tap a button to probe the server',
                            style: TextStyle(color: Colors.white38,
                                fontSize: 11, fontFamily: 'monospace')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        itemCount: _entries.length,
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: e.ok
                                  ? Colors.green.shade900.withOpacity(0.3)
                                  : Colors.red.shade900.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: e.ok
                                    ? Colors.greenAccent.withOpacity(0.3)
                                    : Colors.redAccent.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.title,
                                    style: TextStyle(
                                        color: e.ok ? Colors.greenAccent : Colors.redAccent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                        fontFamily: 'monospace')),
                                const SizedBox(height: 4),
                                SelectableText(e.body,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                        height: 1.5,
                                        fontFamily: 'monospace')),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, Color color) =>
      GestureDetector(
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.45), width: 1),
          ),
          child: Text(label,
              style: TextStyle(color: color,
                  fontWeight: FontWeight.w800, fontSize: 10,
                  fontFamily: 'monospace')),
        ),
      );
}

class _LogEntry {
  final String title, body;
  final bool ok;
  _LogEntry(this.title, this.body, this.ok);
}
