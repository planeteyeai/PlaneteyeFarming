import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/plot_layer_api.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CLUSTER FAB
//  A labeled trigger button that expands into a half-circle of action buttons
//  when tapped. Each cluster has a name, color, icon, and child items.
// ═══════════════════════════════════════════════════════════════════════════

class ClusterFabItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ClusterFabItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class ClusterFab extends StatefulWidget {
  final String clusterName;
  final IconData clusterIcon;
  final Color clusterColor;
  final List<ClusterFabItem> items;
  final bool isOpen;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final double arcStartDeg;
  final double arcEndDeg;
  final double arcRadius;
  final double sizeBox;

  const ClusterFab({
    super.key,
    required this.clusterName,
    required this.clusterIcon,
    required this.clusterColor,
    required this.items,
    required this.isOpen,
    required this.onToggle,
    required this.onClose,
    this.arcStartDeg = 185.0,
    this.arcEndDeg   = 275.0,
    this.arcRadius   = 90.0,
    this.sizeBox     = 200.0,
  });

  @override
  State<ClusterFab> createState() => _ClusterFabState();
}

class _ClusterFabState extends State<ClusterFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rotateAnim = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(ClusterFab old) {
    super.didUpdateWidget(old);
    if (widget.isOpen && !old.isOpen) {
      _ctrl.forward();
    } else if (!widget.isOpen && old.isOpen) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // n items spread from 180° to 270° (left-facing half-arc on right side)
    final n = widget.items.length;

    return SizedBox(
      width: widget.sizeBox,
      height: widget.sizeBox,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // ── Expanded child items ──────────────────────────────
          ...List.generate(n, (i) {
            final startAngle = widget.arcStartDeg * (pi / 180.0);
            final endAngle   = widget.arcEndDeg   * (pi / 180.0);
            final angle = n == 1
                ? (startAngle + endAngle) / 2
                : startAngle + (endAngle - startAngle) * i / (n - 1);

            final radius = widget.arcRadius;
            final dx = cos(angle) * radius;
            final dy = sin(angle) * radius;

            final item = widget.items[i];

            return AnimatedBuilder(
              animation: _expandAnim,
              builder: (_, child) {
                final t = _expandAnim.value;
                return Positioned(
                  right: 10 - dx * t,
                  bottom: 10 - dy * t,
                  child: Opacity(
                    opacity: (_fadeAnim.value).clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: _ClusterChild(item: item, onClose: widget.onClose),
            );
          }),

          // ── Trigger button (always on top) ───────────────────
          Positioned(
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggle,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) => Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            widget.clusterColor,
                            widget.clusterColor.withBlue(
                                (widget.clusterColor.blue * 0.65).round()),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.clusterColor
                                .withOpacity(widget.isOpen ? 0.55 : 0.35),
                            blurRadius: widget.isOpen ? 18 : 10,
                            spreadRadius: widget.isOpen ? 2 : 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white
                              .withOpacity(widget.isOpen ? 0.55 : 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Transform.rotate(
                        angle: _rotateAnim.value * 2 * pi,
                        child: Icon(
                          widget.isOpen ? Icons.close : widget.clusterIcon,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _ClusterLabel(
                  text: widget.clusterName,
                  color: widget.clusterColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterChild extends StatelessWidget {
  final ClusterFabItem item;
  final VoidCallback onClose;

  const _ClusterChild({required this.item, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onClose();
        item.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  item.color,
                  item.color.withOpacity(0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: item.color.withOpacity(0.40),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.30),
                width: 1.2,
              ),
            ),
            child: Icon(item.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 3),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item.label,
              style: const TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _ClusterLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.22),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: color.withOpacity(0.40), width: 0.8),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(0.90),
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAP LAYER CLUSTER BUTTON  (toggle chip style)
// ═══════════════════════════════════════════════════════════════════════════

class MapLayerItem {
  final String label;
  final String emoji;
  final Color color;
  bool active;

  MapLayerItem({
    required this.label,
    required this.emoji,
    required this.color,
    this.active = false,
  });
}

typedef PlotAnalysisLayerCallback = void Function(
  String layerLabel,
  bool active,
  String? tileUrl,
  Map<String, dynamic>? pixelSummary,
);

class MapLayersCluster extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  /// Must match `plot_name` on analysis APIs — use `FieldModel.plotNameForAnalysis`
  /// (from GET plots after login, not the display name only).
  final String plotName;
  /// `end_date` for Soil / Pest APIs (`yyyy-MM-dd`). Defaults to today in parent if omitted.
  final String analysisEndDate;
  final PlotAnalysisLayerCallback onAnalysisLayer;

  const MapLayersCluster({
    super.key,
    required this.isOpen,
    required this.onToggle,
    required this.plotName,
    required this.analysisEndDate,
    required this.onAnalysisLayer,
  });

  @override
  State<MapLayersCluster> createState() => _MapLayersClusterState();
}

class _MapLayersClusterState extends State<MapLayersCluster>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _rotateAnim;

  String? _loadingLabel;

  final List<MapLayerItem> _layers = [
    MapLayerItem(label: 'GROWTH', emoji: '🌱', color: const Color(0xFF43A047)),
    MapLayerItem(label: 'WATER', emoji: '💧', color: const Color(0xFF0288D1)),
    MapLayerItem(label: 'SOIL', emoji: '🟫', color: const Color(0xFF8D6E63)),
    MapLayerItem(label: 'PESTS', emoji: '🐛', color: const Color(0xFFE53935)),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fadeAnim   = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rotateAnim = Tween<double>(begin: 0.0, end: 0.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(MapLayersCluster old) {
    super.didUpdateWidget(old);
    if (widget.isOpen && !old.isOpen) {
      _ctrl.forward();
    } else if (!widget.isOpen && old.isOpen) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onLayerTap(BuildContext context, MapLayerItem layer) async {
    final plot = widget.plotName.trim();
    if (plot.isEmpty) {
      _toast(context, 'Plot name missing — set a plot name matching the server.');
      return;
    }

    if (layer.active) {
      setState(() => layer.active = false);
      widget.onAnalysisLayer(layer.label, false, null, null);
      return;
    }

    setState(() => _loadingLabel = layer.label);
    try {
      final PlotLayerResponse res;
      switch (layer.label) {
        case 'GROWTH':
          res = await PlotLayerApi.fetchGrowth(plot);
          break;
        case 'WATER':
          res = await PlotLayerApi.fetchWater(plot);
          break;
        case 'SOIL':
          res = await PlotLayerApi.fetchSoil(plot, widget.analysisEndDate);
          break;
        case 'PESTS':
          res = await PlotLayerApi.fetchPest(plot, widget.analysisEndDate);
          break;
        default:
          throw const PlotLayerApiException('Unknown layer');
      }

      final url = res.tileUrl;
      if (url == null || url.isEmpty) {
        throw const PlotLayerApiException('No tile_url in API response');
      }

      if (!mounted) return;
      setState(() {
        layer.active = true;
        _loadingLabel = null;
      });
      widget.onAnalysisLayer(layer.label, true, url, res.pixelSummary);
    } catch (e) {
      if (mounted) {
        setState(() => _loadingLabel = null);
        _toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    const clusterColor = Color(0xFF546E7A);
    final n = _layers.length;

    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ...List.generate(n, (i) {
            final startAngle = 185.0 * (pi / 180.0);  // GROWTH fully visible, arc stays within SizedBox
            final endAngle   = 272.0 * (pi / 180.0);
            final angle = startAngle +
                (endAngle - startAngle) * i / (n - 1);
            const radius = 100.0;  // even spacing, no overlap
            final dx = cos(angle) * radius;
            final dy = sin(angle) * radius;
            final layer = _layers[i];

            return AnimatedBuilder(
              animation: _expandAnim,
              builder: (_, child) {
                final t = _expandAnim.value;
                return Positioned(
                  right: 10 - dx * t,
                  bottom: 10 - dy * t,
                  child: Opacity(
                    opacity: _fadeAnim.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _loadingLabel != null
                    ? null
                    : () => _onLayerTap(context, layer),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: layer.active
                              ? [layer.color, layer.color.withOpacity(0.70)]
                              : [
                                  Colors.black.withOpacity(0.55),
                                  Colors.black.withOpacity(0.35)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: layer.active
                                ? layer.color.withOpacity(0.50)
                                : Colors.black.withOpacity(0.25),
                            blurRadius: layer.active ? 12 : 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        border: Border.all(
                          color: layer.active
                              ? layer.color.withOpacity(0.80)
                              : Colors.white.withOpacity(0.20),
                          width: layer.active ? 2.0 : 1.2,
                        ),
                      ),
                      child: Center(
                        child: _loadingLabel == layer.label
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(layer.emoji,
                                style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 44),
                      decoration: BoxDecoration(
                        color: layer.active
                            ? layer.color.withOpacity(0.80)
                            : Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        layer.label,
                        style: const TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // ── Trigger ──────────────────────────────────────────
          Positioned(
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggle,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) => Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            clusterColor,
                            clusterColor.withBlue(20),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: clusterColor.withOpacity(
                                widget.isOpen ? 0.55 : 0.35),
                            blurRadius: widget.isOpen ? 18 : 10,
                            spreadRadius: widget.isOpen ? 2 : 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(
                              widget.isOpen ? 0.55 : 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Transform.rotate(
                        angle: _rotateAnim.value * 2 * pi,
                        child: Icon(
                          widget.isOpen
                              ? Icons.close
                              : Icons.layers_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _ClusterLabel(
                  text: 'FARM STATUS',
                  color: clusterColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
