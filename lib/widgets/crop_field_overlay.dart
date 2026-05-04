import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CROP FIELD OVERLAY  v4  ─  Production-grade animated crop rendering
//
//  KEY DESIGN DECISIONS:
//  1. canvas.clipPath(polygon) is ALWAYS applied first — crops NEVER escape
//  2. Geo-locked plant grid computed once; only LatLng→px projected per frame
//  3. AnimationController drives ALL animation — no setState in render loop
//  4. Each crop family has its own richly-drawn vector plant (not just lines)
//  5. Bitmap path (corn/wheat PNG) for image-backed crops
//  6. Painter's algorithm: back rows drawn first, front rows last (depth)
// ═══════════════════════════════════════════════════════════════════════════

// ─── Global shared wind clock (per field × crop-family) ────────────────────
//
// Keyed by (fieldId, CropFamily) so that:
//   • Two mango plots still share ONE clock → they sway in perfect unison.
//   • A mango plot and a grape plot have SEPARATE clocks → no cross-crop bleed.
//   • Switching fields never leaks a stale clock into the incoming field.
//
// The key is a composite String "fieldId:familyName" so the map stays flat.

class _FamilyClock {
  final AnimationController wind;
  final AnimationController rustle;
  int _refs = 0;

  _FamilyClock({required this.wind, required this.rustle});
}

/// Global registry: key = "<fieldId>:<CropFamily.name>"
final Map<String, _FamilyClock> _familyClocks = {};

String _clockKey(String fieldId, CropFamily family) =>
    '$fieldId:${family.name}';

_FamilyClock _acquireFamilyClock(
    String fieldId, CropFamily family, TickerProvider vsync, Duration windDuration) {
  final key = _clockKey(fieldId, family);
  var clock = _familyClocks[key];
  if (clock == null) {
    clock = _FamilyClock(
      wind: AnimationController(vsync: vsync, duration: windDuration)
        ..repeat(),
      rustle: AnimationController(
              vsync: vsync, duration: const Duration(milliseconds: 900))
          ..repeat(reverse: true),
    );
    _familyClocks[key] = clock;
  }
  clock._refs++;
  return clock;
}

void _releaseFamilyClock(String fieldId, CropFamily family) {
  final key = _clockKey(fieldId, family);
  final clock = _familyClocks[key];
  if (clock == null) return;
  clock._refs--;
  if (clock._refs <= 0) {
    clock.wind.dispose();
    clock.rustle.dispose();
    _familyClocks.remove(key);
  }
}

// ─── Crop family classification ───────────────────────────────────────────

enum CropFamily {
  wheat,      // wheat, barley, oat, rye, millet — dense golden stalks
  rice,       // paddy / rice — shorter, clustered stalks with water feel
  corn,       // maize / corn — tall structured plants with ears
  sugarcane,  // very tall thick cane stalks
  cotton,     // bushy with white bolls
  sunflower,  // tall with large heads
  mustard,    // medium yellow-flower stalks
  legume,     // beans, peas, chickpea, soybean — bushy low plants
  veggie,     // capsicum, chilli, spinach — generic row crops
  brinjal,    // brinjal/eggplant — bitmap plant image in rows
  pepper,     // capsicum/pepper — bitmap plant image in rows
  tomato,     // tomato — dedicated bushy-row renderer with red fruit clusters
  tuber,      // potato, onion, carrot — ground-level foliage
  tree,       // orange, coconut, banana, guava — generic tree canopy
  mango,      // mango orchard — dedicated large-canopy screen-space renderer
  apple,      // apple orchard — bitmap tree image tiled across field
  banana,     // banana plantation — bitmap tree image tiled across field
  coconut,    // coconut palm plantation — bitmap tree image tiled across field
  herb,       // coriander, mint, turmeric — dense low green
  grass,      // generic / pasture
  grape,      // vineyard — long diagonal rows, trellis vines
  cabbage,    // cabbage, cauliflower — large round heads in grid rows
  marigold,   // marigold — tall stems, dense orange ruffled flower heads
  sesame,     // sesame/til — dense upright stalks like tall natural grass, small bell flowers
}

CropFamily _classify(String cropType, [String? fieldName]) {
  final s = '${cropType.toLowerCase()} ${(fieldName ?? '').toLowerCase()}';

  if (s.contains('wheat') || s.contains('gehu') || s.contains('barley') ||
      s.contains('oat')   || s.contains('rye')  || s.contains('millet') ||
      s.contains('bajra') || s.contains('jowar') || s.contains('sorghum'))
    return CropFamily.wheat;

  if (s.contains('rice') || s.contains('paddy') || s.contains('dhan'))
    return CropFamily.rice;

  if (s.contains('maize') || s.contains('corn') || s.contains('makka') ||
      s.contains('bhutta') || s.contains('maka'))
    return CropFamily.corn;

  if (s.contains('sugarcane') || s.contains('ganna'))
    return CropFamily.sugarcane;

  if (s.contains('cotton') || s.contains('kapas'))
    return CropFamily.cotton;

  if (s.contains('sunflower'))
    return CropFamily.sunflower;

  if (s.contains('mustard') || s.contains('canola') || s.contains('sarson') ||
      s.contains('rapeseed') || s.contains('safflower'))
    return CropFamily.mustard;

  if (s.contains('bean')     || s.contains('pea')       || s.contains('chickpea') ||
      s.contains('soybean')  || s.contains('lentil')    || s.contains('groundnut') ||
      s.contains('peanut')   || s.contains('dal')       || s.contains('chana') ||
      s.contains('moong')    || s.contains('tur')       || s.contains('urad'))
    return CropFamily.legume;

  // Cabbage must be checked before veggie to prevent fallthrough
  if (s.contains('cabbage')  || s.contains('cauliflower') || s.contains('bandgobhi') ||
      s.contains('gobhi')    || s.contains('patta')       || s.contains('kale') ||
      s.contains('broccoli') || s.contains('brussels'))
    return CropFamily.cabbage;

  // Tomato gets its own dedicated renderer
  if (s.contains('tomato'))
    return CropFamily.tomato;

  if (s.contains('brinjal') || s.contains('eggplant') || s.contains('baingan') ||
      s.contains('aubergine') || s.contains('begun'))
    return CropFamily.brinjal;

  if (s.contains('capsicum') || s.contains('pepper') ||
      s.contains('shimla')   || s.contains('bell pepper') ||
      s.contains('chilli')   || s.contains('mirch'))
    return CropFamily.pepper;

  if (s.contains('spinach') || s.contains('palak'))
    return CropFamily.veggie;

  if (s.contains('potato')   || s.contains('onion')  || s.contains('carrot') ||
      s.contains('radish')   || s.contains('beet')   || s.contains('turnip') ||
      s.contains('garlic')   || s.contains('ginger') || s.contains('yam')    ||
      s.contains('tapioca'))
    return CropFamily.tuber;

  if (s.contains('grape') || s.contains('grapes') || s.contains('vineyard') ||
      s.contains('vine')  || s.contains('angur')  || s.contains('draksha'))
    return CropFamily.grape;

  // Mango gets its own dedicated orchard renderer
  if (s.contains('mango') || s.contains('aam') || s.contains('kesar') ||
      s.contains('alphonso') || s.contains('dasheri') || s.contains('langra'))
    return CropFamily.mango;

  if (s.contains('apple') || s.contains('seb') || s.contains('kashmiri apple') ||
      s.contains('fuji') || s.contains('shimla'))
    return CropFamily.apple;

  if (s.contains('banana') || s.contains('kela') || s.contains('plantain') ||
      s.contains('keli') || s.contains('balehannu'))
    return CropFamily.banana;

  if (s.contains('coconut') || s.contains('nariyal') || s.contains('naral') ||
      s.contains('tengai') || s.contains('thengai') || s.contains('copra'))
    return CropFamily.coconut;

  if (s.contains('orange')  || s.contains('lemon') ||
      s.contains('banana')   || s.contains('coconut') || s.contains('papaya') ||
      s.contains('guava')    || s.contains('pomegranate') || s.contains('apple') ||
      s.contains('grape')    || s.contains('anjeer')  || s.contains('amrud') ||
      s.contains('horticulture') || s.contains('orchard') || s.contains('fruit'))
    return CropFamily.tree;

  if (s.contains('marigold') || s.contains('genda')   || s.contains('zendu') ||
      s.contains('tagetes')  || s.contains('calendula'))
    return CropFamily.marigold;

  if (s.contains('sesame')  || s.contains('til')     || s.contains('teel') ||
      s.contains('gingelly') || s.contains('sesamum') || s.contains('sim sim'))
    return CropFamily.sesame;

  if (s.contains('mint')     || s.contains('basil')     || s.contains('coriander') ||
      s.contains('turmeric') || s.contains('fennel')    || s.contains('fenugreek') ||
      s.contains('methi')    || s.contains('dhaniya')   || s.contains('jeera') ||
      s.contains('herb'))
    return CropFamily.herb;

  return CropFamily.grass;
}

// ─── Image cache (singleton) ──────────────────────────────────────────────

class _ImgCache {
  static final Map<String, ui.Image?> _done = {};
  static final Map<String, Future<ui.Image?>> _loading = {};

  static Future<ui.Image?> get(String path) {
    if (_done.containsKey(path)) return Future.value(_done[path]);
    return _loading.putIfAbsent(path, () async {
      try {
        final d = await rootBundle.load(path);
        final c = await ui.instantiateImageCodec(d.buffer.asUint8List());
        final f = await c.getNextFrame();
        _done[path] = f.image;
      } catch (_) { _done[path] = null; }
      _loading.remove(path);
      return _done[path];
    });
  }
}

// ─── Plant instance (geo-locked, computed once) ───────────────────────────

class _Plant {
  final LatLng ll;
  final double rot;        // static tilt radians
  final double scale;      // 0.8–1.2
  final double phase;      // wind phase offset 0–2π
  final double rowFrac;    // 0=back, 1=front
  final double opacity;    // 0.8–1.0
  final int    variant;    // per-plant variety (0,1,2) for slight variation

  const _Plant({
    required this.ll, required this.rot, required this.scale,
    required this.phase, required this.rowFrac,
    required this.opacity, required this.variant,
  });
}

// ─── Widget ───────────────────────────────────────────────────────────────

class CropFieldLayer extends StatefulWidget {
  final List<LatLng> polygon;
  final String cropType;
  final String? fieldName;
  /// Unique identifier for the owning field/plot.  Used to scope animation
  /// clocks so that Plot A's mango animation never bleeds into Plot B.
  /// Defaults to empty string for backward compatibility.
  final String fieldId;
  final double windSpeedMs;
  final double windDeg;
  /// When true, soil/background fill is skipped so the heatmap below
  /// shows through and merges with the crop plant animation on top.
  final bool heatmapActive;
  /// Optional asset path for a custom image to tile across the entire polygon
  /// (e.g. 'assets/images/maize_field.png').  When set, the image is stamped
  /// at every plant grid position, clipped strictly to the polygon boundary.
  final String? imagePath;
  /// Farmer-entered spacing in metres. 0 = use crop-type default.
  final double rowSpacingM;
  final double plantSpacingM;
  /// ISO date string e.g. "2026-04-01". If within 21 days of today,
  /// the seedling image is used instead of the crop-specific animation.
  final String? plantationDate;

  const CropFieldLayer({
    super.key,
    required this.polygon,
    required this.cropType,
    this.fieldName,
    this.fieldId        = '',
    this.windSpeedMs    = 3.0,
    this.windDeg        = 270.0,
    this.heatmapActive  = false,
    this.imagePath,
    this.rowSpacingM    = 0.0,
    this.plantSpacingM  = 0.0,
    this.plantationDate,
  });

  @override
  State<CropFieldLayer> createState() => _CropFieldLayerState();
}

class _CropFieldLayerState extends State<CropFieldLayer>
    with TickerProviderStateMixin {

  // Shared clock — all fields of the same crop family share one
  // AnimationController so their wind sway is perfectly in sync.
  _FamilyClock? _clock;

  CropFamily _family = CropFamily.grass;
  List<_Plant> _plants = [];
  ui.Image? _bitmapImg;
  ui.Image? _seedlingImg;
  ui.Image? _grapeRowImg;
  bool _usesBitmap = false;

  /// True if the plantation date is within 21 days of today.
  bool get _isSeedlingStage {
    final dateStr = widget.plantationDate;
    if (dateStr == null || dateStr.isEmpty) return false;
    try {
      final planted = DateTime.parse(dateStr);
      final days = DateTime.now().difference(planted).inDays;
      return days >= 0 && days <= 21;
    } catch (_) { return false; }
  }
  ui.Image? _customImg;   // loaded when widget.imagePath != null

  // The painter is kept as a field so we can push new values to it
  // without rebuilding the widget tree — only the CustomPaint repaints.
  _FieldPainter? _painter;

  AnimationController get _windCtrl   => _clock!.wind;
  AnimationController get _rustleCtrl => _clock!.rustle;

  @override
  void initState() {
    super.initState();
    _rebuild(); // _rebuild acquires the shared clock for the resolved family
  }

  void _acquireClock(CropFamily family) {
    // Detach from old clock if the crop family changed
    if (_clock != null) {
      _windCtrl.removeListener(_onAnim);
      _rustleCtrl.removeListener(_onAnim);
      _releaseFamilyClock(widget.fieldId, _family);
      _clock = null;
    }
    final windDuration = Duration(
        milliseconds:
            (3500 - widget.windSpeedMs * 120).round().clamp(1800, 7000));
    _clock = _acquireFamilyClock(widget.fieldId, family, this, windDuration);
    _windCtrl.addListener(_onAnim);
    _rustleCtrl.addListener(_onAnim);
  }

  void _onAnim() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CropFieldLayer old) {
    super.didUpdateWidget(old);
    if (old.cropType != widget.cropType ||
        old.fieldName != widget.fieldName ||
        !_polyEq(old.polygon, widget.polygon) ||
            old.rowSpacingM != widget.rowSpacingM ||
            old.plantSpacingM != widget.plantSpacingM ||
            old.plantationDate != widget.plantationDate) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    if (_clock != null) {
      _windCtrl.removeListener(_onAnim);
      _rustleCtrl.removeListener(_onAnim);
      _releaseFamilyClock(widget.fieldId, _family);
      _clock = null;
    }
    super.dispose();
  }

  void _rebuild() {
    // ── Seedling stage override ───────────────────────────────────────────
    // If planted within 21 days, show the seedling image across the whole field
    if (_isSeedlingStage) {
      _family = CropFamily.grass;  // minimal base
      _usesBitmap = false;
      // Use tight spacing so seedlings are dense (0.3m x 0.3m)
      final spacing = widget.rowSpacingM > 0
          ? (widget.rowSpacingM, widget.plantSpacingM > 0 ? widget.plantSpacingM : widget.rowSpacingM)
          : (0.30, 0.30);
      _plants = _buildGrid(widget.polygon, spacing.$1, spacing.$2);
      // Load seedling bitmap
      _ImgCache.get('assets/crops/seedling.png').then((img) {
        if (mounted) setState(() => _seedlingImg = img);
      });
      _acquireClock(_family);
      if (mounted) setState(() {});
      return;
    }

    _family = _classify(widget.cropType, widget.fieldName);
    _usesBitmap = _family == CropFamily.corn || _family == CropFamily.wheat || _family == CropFamily.grape || _family == CropFamily.brinjal || _family == CropFamily.tomato || _family == CropFamily.pepper;
    // Attach to (or switch to) the shared clock for this crop family.
    // All fields of the same family will share one AnimationController,
    // ensuring their wind animation runs in perfect lockstep.
    _acquireClock(_family);

    // Grape vineyard — bitmap image tiled in straight rows across field.
    if (_family == CropFamily.grape) {
      _plants = _buildGrid(widget.polygon, 2.5, 2.0);
      _ImgCache.get('assets/crops/grape_tree.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Brinjal — bitmap image tiled in rows like coconut/grape.
    if (_family == CropFamily.brinjal) {
      _plants = _buildGrid(widget.polygon, 1.2, 1.0);
      _usesBitmap = true;
      _ImgCache.get('assets/crops/brinjal_plant.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Pepper — bitmap image tiled in rows like coconut/brinjal.
    if (_family == CropFamily.pepper) {
      _plants = _buildGrid(widget.polygon, 0.90, 0.75);
      _usesBitmap = true;
      _ImgCache.get('assets/crops/pepper_plant.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Cabbage uses a pure screen-space grid renderer — same pattern as grape.
    if (_family == CropFamily.cabbage) {
      _plants = _buildGrid(widget.polygon, 0.6, 0.6);
      if (mounted) setState(() {});
      return;
    }

    // Marigold uses a pure screen-space row renderer.
    if (_family == CropFamily.marigold) {
      _plants = _buildGrid(widget.polygon, 0.35, 0.30);
      if (mounted) setState(() {});
      return;
    }

    // Sesame uses a pure screen-space dense-grass renderer.
    if (_family == CropFamily.sesame) {
      _plants = _buildGrid(widget.polygon, 0.30, 0.10);
      if (mounted) setState(() {});
      return;
    }

    // Mango uses its own screen-space orchard renderer with bitmap trees.
    if (_family == CropFamily.mango) {
      _plants = _buildGrid(widget.polygon, 6.0, 6.0);
      _ImgCache.get('assets/crops/mango_tree.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Apple orchard — same bitmap approach as mango
    if (_family == CropFamily.apple) {
      _plants = _buildGrid(widget.polygon, 5.0, 5.0);
      _ImgCache.get('assets/crops/apple_tree.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Coconut palm plantation
    if (_family == CropFamily.coconut) {
      _plants = _buildGrid(widget.polygon, 7.0, 7.0);
      _ImgCache.get('assets/crops/coconut_tree.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Banana plantation — tall trees, moderate spacing
    if (_family == CropFamily.banana) {
      _plants = _buildGrid(widget.polygon, 3.0, 2.5);
      _ImgCache.get('assets/crops/banana_tree.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Tomato — bitmap image tiled in rows like coconut/brinjal.
    if (_family == CropFamily.tomato) {
      _plants = _buildGrid(widget.polygon, 0.90, 0.75);
      _usesBitmap = true;
      _ImgCache.get('assets/crops/tomato_plant.png')
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
      if (mounted) setState(() {});
      return;
    }

    // Determine spacing: farmer-entered > imagePath default > crop default
    (double, double) spacing;
    if (widget.rowSpacingM > 0 || widget.plantSpacingM > 0) {
      final def = _spacingFor(_family);
      spacing = (
        widget.rowSpacingM   > 0 ? widget.rowSpacingM   : def.$1,
        widget.plantSpacingM > 0 ? widget.plantSpacingM : def.$2,
      );
    } else if (widget.imagePath != null) {
      spacing = (1.20, 1.00);
    } else {
      spacing = _spacingFor(_family);
    }
    _plants = _buildGrid(widget.polygon, spacing.$1, spacing.$2);

    // Load custom image (takes priority over bitmap crop images)
    if (widget.imagePath != null) {
      _ImgCache.get(widget.imagePath!)
          .then((img) { if (mounted) setState(() => _customImg = img); });
    } else if (_usesBitmap) {
      final path = _family == CropFamily.corn
          ? 'assets/crops/corn.png'
          : 'assets/crops/wheat.png';
      _ImgCache.get(path)
          .then((img) { if (mounted) setState(() => _bitmapImg = img); });
    }
    if (mounted) setState(() {});
  }

  static (double rowM, double colM) _spacingFor(CropFamily f) {
    switch (f) {
      case CropFamily.wheat:     return (0.20, 0.18);
      case CropFamily.rice:      return (0.22, 0.20);
      case CropFamily.corn:      return (1.20, 1.00);
      case CropFamily.sugarcane: return (1.20, 0.60);
      case CropFamily.cotton:    return (1.00, 0.90);
      case CropFamily.sunflower: return (0.70, 0.60);
      case CropFamily.mustard:   return (0.28, 0.25);
      case CropFamily.legume:    return (0.40, 0.35);
      case CropFamily.veggie:    return (0.50, 0.45);
      case CropFamily.tomato:    return (0.60, 0.55);
      case CropFamily.tuber:     return (0.30, 0.28);
      case CropFamily.tree:      return (4.00, 4.00);
      case CropFamily.mango:     return (6.00, 6.00);
      case CropFamily.apple:     return (5.00, 5.00);
      case CropFamily.banana:    return (3.00, 2.50);
      case CropFamily.coconut:   return (7.00, 7.00);
      case CropFamily.herb:      return (0.18, 0.16);
      case CropFamily.grass:     return (0.14, 0.12);
      case CropFamily.grape:     return (2.00, 1.00); // wide rows, tight in-row
      case CropFamily.brinjal:   return (1.20, 1.00); // brinjal row spacing
      case CropFamily.pepper:    return (0.90, 0.75); // pepper row spacing
      case CropFamily.cabbage:   return (0.60, 0.60); // medium grid — heads need room
      case CropFamily.marigold:  return (0.35, 0.30); // medium-dense rows
      case CropFamily.sesame:    return (0.30, 0.10); // dense in-row, moderate row gap
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.polygon.length < 3) return const SizedBox.shrink();
    // Screen-space renderers (grape, cabbage, etc.) don't use the plant grid.
    const screenSpace = {
      CropFamily.cabbage, CropFamily.marigold,
      CropFamily.sesame, CropFamily.mango,
      CropFamily.apple, CropFamily.banana, CropFamily.coconut,
    };
    if (_plants.isEmpty && !screenSpace.contains(_family)) {
      return const SizedBox.shrink();
    }
    // Wait for custom image to load before painting
    if (widget.imagePath != null && _customImg == null) {
      return const SizedBox.shrink();
    }
    // Only wait for bitmap if this family truly needs it (wheat/corn PNGs).
    // All screen-space renderers (grape, cabbage, marigold, sesame, tomato,
    // mango-fallback) draw without bitmaps so they must NOT be blocked.
    // If in seedling stage, wait for the seedling image
    if (_isSeedlingStage) {
      if (_seedlingImg == null) return const SizedBox.shrink();
    } else if (_usesBitmap && widget.imagePath == null && _bitmapImg == null &&
        _family != CropFamily.cabbage  &&
        _family != CropFamily.marigold && _family != CropFamily.sesame  &&
        _family != CropFamily.mango   &&
        _family != CropFamily.apple    && _family != CropFamily.banana   &&
        _family != CropFamily.coconut) {
      return const SizedBox.shrink();
    }

    // ── CRITICAL: read MapCamera here at build() level ───────────────────
    // This context IS registered as an InheritedWidget dependent of the map,
    // so Flutter calls build() on EVERY camera change (pan, pinch, fling,
    // rotation). All pixel projection happens here — never inside a builder
    // callback — so positions are always frame-accurate.
    final cam = MapCamera.of(context);

    // Project all geo-coordinates to current screen pixels
    final polyPx = _projectPoly(widget.polygon, cam);
    final mpp = _mpp(
      widget.polygon.map((e) => e.latitude).reduce((a, b) => a + b) /
          widget.polygon.length,
      cam.zoom,
    );
    final px = _plants.map((p) {
      final sp = cam.latLngToScreenPoint(p.ll);
      return _PxPlant(Offset(sp.x.toDouble(), sp.y.toDouble()), p);
    }).toList(growable: false);

    // ── NO MobileLayerTransformer ────────────────────────────────────────
    // MobileLayerTransformer applies an additional Transform (translation +
    // scale) that is computed SEPARATELY from latLngToScreenPoint(). During
    // a pinch gesture the two transforms diverge for several frames, which
    // is exactly what causes the "floating" artefact. By omitting it and
    // painting directly in screen space (which latLngToScreenPoint already
    // returns) the overlay is always pixel-perfect.
    //
    // We use a plain IgnorePointer → ClipPath → CustomPaint stack.
    // The ClipPath is the hard polygon boundary — nothing can ever paint
    // outside it regardless of sway animation values.
    return IgnorePointer(
      child: ClipPath(
        clipper: _PolygonClipper(polyPx),
        child: CustomPaint(
          painter: _FieldPainter(
            family:        _family,
            polygonPx:     polyPx,
            plants:        px,
            wind:          _windCtrl.value,
            rustle:        _rustleCtrl.value,
            windSpeedMs:   widget.windSpeedMs,
            windDeg:       widget.windDeg,
            mpp:           mpp,
            bitmapImg:     _bitmapImg,
            customImg:     _customImg,
            seedlingImg:   _isSeedlingStage ? _seedlingImg : null,
            grapeRowImg:   _grapeRowImg,
            heatmapActive: widget.heatmapActive,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ─── Screen-projected plant (per frame) ───────────────────────────────────

class _PxPlant {
  final Offset px;
  final _Plant p;
  const _PxPlant(this.px, this.p);
}

// ─── Marigold plant position (for painter's-algorithm sort) ──────────────

class _MarigoldPos {
  final Offset pos;
  final double scale;
  final double bloom; // 0=bud, 1=fully open
  const _MarigoldPos(this.pos, this.scale, this.bloom);
}

// ─── Polygon clipper (widget-level outer fence) ────────────────────────────
//
// Used as the clipper for the ClipPath widget that wraps the CustomPaint.
// By providing the already-projected screen-space polygon vertices we get
// a zero-overhead GPU-level scissor that matches the canvas.clipPath used
// inside the painter — double-fencing crops inside the field boundary.

// latlong2 exports its own `Path` type which shadows dart:ui's Path,
// so we must use the `ui.` prefix everywhere we mean the canvas Path.
class _PolygonClipper extends CustomClipper<ui.Path> {
  final List<Offset> polyPx;

  _PolygonClipper(this.polyPx);

  @override
  ui.Path getClip(Size size) {
    if (polyPx.isEmpty) return ui.Path();
    final path = ui.Path()..moveTo(polyPx.first.dx, polyPx.first.dy);
    for (var i = 1; i < polyPx.length; i++) {
      path.lineTo(polyPx[i].dx, polyPx[i].dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_PolygonClipper old) {
    if (old.polyPx.length != polyPx.length) return true;
    for (var i = 0; i < polyPx.length; i++) {
      if (old.polyPx[i] != polyPx[i]) return true;
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FIELD PAINTER — single CustomPainter that handles ALL crop families
// ═══════════════════════════════════════════════════════════════════════════

class _FieldPainter extends CustomPainter {
  final CropFamily family;
  final List<Offset> polygonPx;
  final List<_PxPlant> plants;
  final double wind;          // 0→1 main sway cycle
  final double rustle;        // 0→1 micro-rustle cycle
  final double windSpeedMs;
  final double windDeg;
  final double mpp;           // metres per pixel (for sizing)
  final ui.Image? bitmapImg;
  final ui.Image? customImg;  // tiled image (takes priority over bitmapImg)
  final ui.Image? seedlingImg; // used when plantation date is within 21 days
  final ui.Image? grapeRowImg; // horizontal trellis row image for vineyards
  /// When true, skip all soil/background fill so heatmap shows through.
  final bool heatmapActive;

  // Pre-computed wind direction vector
  late final double _leanSign;
  late final double _speedN;
  late final Rect   _srcRect;

  _FieldPainter({
    required this.family,
    required this.polygonPx,
    required this.plants,
    required this.wind,
    required this.rustle,
    required this.windSpeedMs,
    required this.windDeg,
    required this.mpp,
    required this.bitmapImg,
    this.customImg,
    this.seedlingImg,
    this.grapeRowImg,
    this.heatmapActive = false,
  }) {
    final rad = (windDeg + 180.0) * pi / 180.0;
    _leanSign = sin(rad) >= 0 ? 1.0 : -1.0;
    _speedN   = (windSpeedMs / 12.0).clamp(0.0, 1.0);
    final activeImg = customImg ?? bitmapImg;
    if (activeImg != null) {
      _srcRect = Rect.fromLTWH(
          0, 0, activeImg.width.toDouble(), activeImg.height.toDouble());
    } else {
      _srcRect = Rect.zero;
    }
  }

  // Clip path built once per paint call
  ui.Path _clipPath() {
    final p = ui.Path()
      ..moveTo(polygonPx.first.dx, polygonPx.first.dy);
    for (var i = 1; i < polygonPx.length; i++) {
      p.lineTo(polygonPx[i].dx, polygonPx[i].dy);
    }
    return p..close();
  }

  Rect _polyBounds() {
    var l = polygonPx.first.dx, t = polygonPx.first.dy,
        r = l, b = t;
    for (final v in polygonPx) {
      if (v.dx < l) l = v.dx;
      if (v.dx > r) r = v.dx;
      if (v.dy < t) t = v.dy;
      if (v.dy > b) b = v.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (polygonPx.length < 3) return;
    // Screen-space renderers (grape, cabbage, marigold, etc.) don't use the
    // plant grid — only bail on empty plants for geo-grid families.
    if (plants.isEmpty &&
        family != CropFamily.cabbage  &&
        family != CropFamily.marigold && family != CropFamily.sesame  &&
        family != CropFamily.mango   &&
        family != CropFamily.apple    && family != CropFamily.banana   &&
        family != CropFamily.coconut) return;

    final clip   = _clipPath();
    final bounds = _polyBounds();

    // ── Seedling stage — newly planted crop overlay ──────────────────────
    if (seedlingImg != null) {
      _drawSeedlingField(canvas, bounds, clip);
      return;
    }

    // ── Grape vineyard — bitmap image in straight rows like coconut ──
    if (family == CropFamily.grape) {
      canvas.save();
      canvas.clipPath(clip);
      _drawGrapeBitmapField(canvas, bounds, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Brinjal field — bitmap plant image in rows like coconut ─────
    if (family == CropFamily.brinjal) {
      canvas.save();
      canvas.clipPath(clip);
      _drawBrinjalBitmapField(canvas, bounds, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Pepper field — bitmap plant image in rows ────────────────────
    if (family == CropFamily.pepper) {
      canvas.save();
      canvas.clipPath(clip);
      _drawPepperBitmapField(canvas, bounds, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Cabbage field — screen-space grid renderer ────────────────────
    if (family == CropFamily.cabbage) {
      canvas.save();
      canvas.clipPath(clip);
      _drawCabbageField(canvas, bounds, size, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Marigold field — geo-locked row renderer ──────────────────────
    if (family == CropFamily.marigold) {
      canvas.save();
      canvas.clipPath(clip);
      _drawMarigoldField(canvas, bounds, size, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Sesame / til field — dense upright grass-like stalks ─────────
    if (family == CropFamily.sesame) {
      canvas.save();
      canvas.clipPath(clip);
      _drawSesameField(canvas, bounds, size, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Mango orchard — bitmap tree image tiled across field ────────────
    if (family == CropFamily.mango) {
      if (bitmapImg != null) {
        canvas.save();
        canvas.clipPath(clip);
        _drawMangoBitmapOrchard(canvas, bounds, clip);
        canvas.restore();
      }
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.40)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Apple orchard — same bitmap renderer as mango ────────────────────
    if (family == CropFamily.apple) {
      if (bitmapImg != null) {
        canvas.save();
        canvas.clipPath(clip);
        _drawMangoBitmapOrchard(canvas, bounds, clip);
        canvas.restore();
      }
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.40)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Coconut palm plantation — bitmap tree tiled across field ────────
    if (family == CropFamily.coconut) {
      if (bitmapImg != null) {
        canvas.save();
        canvas.clipPath(clip);
        _drawMangoBitmapOrchard(canvas, bounds, clip);
        canvas.restore();
      }
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.40)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Banana plantation — bitmap tree tiled across field ───────────────
    if (family == CropFamily.banana) {
      if (bitmapImg != null) {
        canvas.save();
        canvas.clipPath(clip);
        _drawMangoBitmapOrchard(canvas, bounds, clip);
        canvas.restore();
      }
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.40)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── Tomato field — bushy rows with red fruit clusters ──────────────
    if (family == CropFamily.tomato) {
      canvas.save();
      canvas.clipPath(clip);
      _drawTomatoBitmapField(canvas, bounds, clip, heatmapActive: heatmapActive);
      canvas.restore();
      canvas.drawPath(clip, Paint()
        ..color = const Color(0xFF76FF03).withOpacity(0.50)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke);
      return;
    }

    // ── 1. Soil base — skipped when heatmap is active so the heat-map
    //    tile below shows through and merges with the crop animation.
    if (!heatmapActive) {
      canvas.save();
      canvas.clipPath(clip);
      _drawSoil(canvas, bounds, clip);
      canvas.restore();
    }

    // ── 2. Plants (ALSO clipped — crops NEVER leave polygon) ───────────
    canvas.save();
    canvas.clipPath(clip);

    // Generous expansion: plants near polygon edges must never be culled
    // by the screen-bounds check even if their center is slightly outside.
    final screen = Rect.fromLTWH(-200, -200, size.width + 400, size.height + 400);

    if (customImg != null) {
      _drawImageTile(canvas, screen, customImg!);
    } else if (bitmapImg != null) {
      _drawBitmapPlants(canvas, screen);
    } else {
      _drawVectorPlants(canvas, screen, bounds);
    }

    canvas.restore();

    // ── 3. Field border (drawn OUTSIDE clip so it's always visible) ────
    canvas.drawPath(clip, Paint()
      ..color = const Color(0xFF76FF03).withOpacity(0.50)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  VINEYARD RENDERER — geo-locked diagonal row system
  //
  //  All sizes derived from mpp so the field stays stable across zooms.
  //  Real-world vine spacing:
  //    Row gap   : ~2.0 m  →  rowGap_px   = 2.0 / mpp
  //    Plant gap : ~1.0 m  →  plantGap_px = 1.0 / mpp
  // ═══════════════════════════════════════════════════════════════════════

  // ── Grape row field — tiles the trellis row image in horizontal strips ─────
  // The grape_row image is a wide horizontal trellis row (poles + vines + fruit).
  // We repeat it across the field width and stack rows top-to-bottom with spacing,
  // giving an authentic top-down vineyard look.
  void _drawGrapeRowField(Canvas canvas, Rect bounds, ui.Path clip) {
    final img = grapeRowImg!;
    final imgW = img.width.toDouble();
    final imgH = img.height.toDouble();
    final srcRect = Rect.fromLTWH(0, 0, imgW, imgH);

    // Row height in pixels: 2m row spacing → pixel size
    final rowHeightPx = (2.2 / mpp).clamp(18.0, 60.0);
    // Aspect ratio of the source image (width > height for a horizontal row)
    final rowWidthPx  = rowHeightPx * (imgW / imgH);

    // Soil background — warm vineyard earth
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF6B4A28).withOpacity(0.85));

    // Wind sway — gentle horizontal shift on each row
    final sway = sin(wind * pi * 2) * _speedN * 3.0 * _leanSign;

    // Tile rows top to bottom across the entire bounding box
    double rowY = bounds.top;
    int rowIndex = 0;
    while (rowY < bounds.bottom + rowHeightPx) {
      // Slight perspective scale — rows at bottom are slightly larger
      final t = ((rowY - bounds.top) / bounds.height).clamp(0.0, 1.0);
      final depthScale = 0.80 + t * 0.20;
      final rH = rowHeightPx * depthScale;
      final rW = rowWidthPx  * depthScale;

      // Wind offset alternates slightly between rows
      final rowSway = sway * (rowIndex.isEven ? 1.0 : 0.85);

      // Tile this row image across the full field width
      double tileX = bounds.left - rW * 0.5 + rowSway;
      while (tileX < bounds.right + rW) {
        final dst = Rect.fromLTWH(tileX, rowY, rW, rH);
        // Clip to field polygon already applied by canvas.clipPath
        canvas.drawImageRect(img, srcRect, dst, Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255,
              (0.82 + t * 0.15).clamp(0.0, 1.0)));
        tileX += rW * 0.92; // slight overlap between tiles for seamless look
      }

      rowY += rH * 1.08; // row-to-row gap (8% of row height = inter-row soil strip)
      rowIndex++;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  GRAPE BITMAP FIELD — grape_tree.png tiled in strict straight rows
  //
  //  Identical approach to coconut/mango bitmap orchard but:
  //    • Straight rows (no stagger) for vineyard look
  //    • Soil background + furrow stripes fill the field
  //    • Each plant drawn back-to-front with depth scale + wind sway
  //    • Image has transparent background → blends cleanly over soil
  // ═══════════════════════════════════════════════════════════════════════

  void _drawGrapeBitmapField(Canvas canvas, Rect b, ui.Path clip, {bool heatmapActive = false}) {
    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF4E342E);
    const soilLight = Color(0xFF6D4C41);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Furrow stripes between rows ────────────────────────────────
    if (!heatmapActive) {
      final treeH = (3.5 / mpp).clamp(24.0, 100.0);
      final rowGap = treeH * 1.15;
      final furrowPaint = Paint()
        ..color = const Color(0xFF3E2723).withOpacity(0.28)
        ..strokeWidth = rowGap * 0.22
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    // ── 3. Draw plants back→front using geo-locked plant grid ─────────
    if (bitmapImg == null) return;
    final img = bitmapImg!;
    final srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    // Tree render size — grape vine ~3.5m tall in real world
    final treeH   = (3.5 / mpp).clamp(24.0, 100.0);
    final aspect  = img.height / img.width;
    final treeW   = treeH / aspect;

    // Wind sway — gentle, trellis-trained vines move less than palms
    final globalSway = sin(wind * pi * 2) * _speedN * 2.0 * _leanSign;

    // Sort plant list back-to-front (higher screen Y = closer = draw on top)
    final sorted = List.of(plants)
      ..sort((a, b) => a.px.dy.compareTo(b.px.dy));

    for (final p in sorted) {
      final x = p.px.dx;
      final y = p.px.dy;

      // Cull plants far outside viewport
      if (x < b.left  - treeW  || x > b.right  + treeW ||
          y < b.top   - treeH  || y > b.bottom + treeH) continue;

      // Depth scale — front rows bigger
      final depthFrac  = ((y - b.top) / (b.height + 1)).clamp(0.0, 1.0);
      final depthScale = 0.72 + depthFrac * 0.28;

      final dW = treeW * depthScale;
      final dH = treeH * depthScale;

      // Per-plant phase from stored plant data for variety
      final swayX = globalSway * depthScale * (0.5 + p.p.phase * 0.3);

      // Opacity slightly deeper for back rows (atmospheric depth)
      final opacity = (0.80 + depthFrac * 0.20).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x + swayX, y);

      final dstRect = Rect.fromCenter(
        center: Offset(0, -dH * 0.48),
        width:  dW,
        height: dH,
      );

      canvas.drawImageRect(img, srcRect, dstRect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));

      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TOMATO BITMAP FIELD — tomato_plant.png tiled in straight rows
  //
  //  Real-world spacing: ~0.9m row gap, ~0.75m plant gap
  //  Soil: dark rich earth, furrow stripes between rows
  // ═══════════════════════════════════════════════════════════════════════

  void _drawTomatoBitmapField(Canvas canvas, Rect b, ui.Path clip, {bool heatmapActive = false}) {
    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF3E2723);
    const soilLight = Color(0xFF5D4037);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Furrow stripes ──────────────────────────────────────────────
    if (!heatmapActive) {
      final plantH = (0.9 / mpp).clamp(14.0, 55.0);
      final rowGap = plantH * 1.15;
      final furrowPaint = Paint()
        ..color = const Color(0xFF1A0A00).withOpacity(0.28)
        ..strokeWidth = rowGap * 0.18
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    // ── 3. Draw plants back→front ──────────────────────────────────────
    if (bitmapImg == null) return;
    final img     = bitmapImg!;
    final srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    final plantH  = (0.9 / mpp).clamp(14.0, 55.0);
    final aspect  = img.height / img.width;
    final plantW  = plantH / aspect;

    final globalSway = sin(wind * pi * 2) * _speedN * 1.2 * _leanSign;

    final sorted = List.of(plants)
      ..sort((a, b) => a.px.dy.compareTo(b.px.dy));

    for (final p in sorted) {
      final x = p.px.dx;
      final y = p.px.dy;

      if (x < b.left - plantW || x > b.right + plantW ||
          y < b.top  - plantH || y > b.bottom + plantH) continue;

      final depthFrac  = ((y - b.top) / (b.height + 1)).clamp(0.0, 1.0);
      final depthScale = 0.75 + depthFrac * 0.25;
      final dW    = plantW * depthScale;
      final dH    = plantH * depthScale;
      final swayX = globalSway * depthScale * (0.5 + p.p.phase * 0.3);
      final opacity = (0.82 + depthFrac * 0.18).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x + swayX, y);
      canvas.drawImageRect(img, srcRect,
          Rect.fromCenter(center: Offset(0, -dH * 0.48), width: dW, height: dH),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));
      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  PEPPER BITMAP FIELD — pepper_plant.png tiled in straight rows
  //
  //  Real-world spacing: ~0.9m row gap, ~0.75m plant gap
  // ═══════════════════════════════════════════════════════════════════════

  void _drawPepperBitmapField(Canvas canvas, Rect b, ui.Path clip, {bool heatmapActive = false}) {
    const soilDark  = Color(0xFF3E2723);
    const soilLight = Color(0xFF5D4037);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    if (!heatmapActive) {
      final plantH = (0.9 / mpp).clamp(14.0, 60.0);
      final rowGap = plantH * 1.15;
      final furrowPaint = Paint()
        ..color = const Color(0xFF1A0A00).withOpacity(0.28)
        ..strokeWidth = rowGap * 0.18
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    if (bitmapImg == null) return;
    final img     = bitmapImg!;
    final srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final plantH  = (0.9 / mpp).clamp(14.0, 60.0);
    final aspect  = img.height / img.width;
    final plantW  = plantH / aspect;
    final globalSway = sin(wind * pi * 2) * _speedN * 1.2 * _leanSign;

    final sorted = List.of(plants)..sort((a, b) => a.px.dy.compareTo(b.px.dy));

    for (final p in sorted) {
      final x = p.px.dx;
      final y = p.px.dy;
      if (x < b.left - plantW || x > b.right + plantW ||
          y < b.top  - plantH || y > b.bottom + plantH) continue;

      final depthFrac  = ((y - b.top) / (b.height + 1)).clamp(0.0, 1.0);
      final depthScale = 0.75 + depthFrac * 0.25;
      final dW    = plantW * depthScale;
      final dH    = plantH * depthScale;
      final swayX = globalSway * depthScale * (0.5 + p.p.phase * 0.3);
      final opacity = (0.82 + depthFrac * 0.18).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x + swayX, y);
      canvas.drawImageRect(img, srcRect,
          Rect.fromCenter(center: Offset(0, -dH * 0.48), width: dW, height: dH),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));
      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BRINJAL BITMAP FIELD — brinjal_plant.png tiled in straight rows
  //
  //  Identical approach to grape/coconut bitmap orchard:
  //    • Soil background fills the field
  //    • Straight rows with slight furrow stripes
  //    • Each plant back-to-front with depth scale + wind sway
  //    • Transparent PNG blends cleanly over soil
  //  Real-world spacing: ~1.2m row gap, ~1.0m plant gap
  // ═══════════════════════════════════════════════════════════════════════

  void _drawBrinjalBitmapField(Canvas canvas, Rect b, ui.Path clip, {bool heatmapActive = false}) {
    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF3E2723);
    const soilLight = Color(0xFF5D4037);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Furrow stripes ──────────────────────────────────────────────
    if (!heatmapActive) {
      final plantH = (1.2 / mpp).clamp(18.0, 70.0);
      final rowGap = plantH * 1.20;
      final furrowPaint = Paint()
        ..color = const Color(0xFF1A0A00).withOpacity(0.30)
        ..strokeWidth = rowGap * 0.20
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    // ── 3. Draw plants back→front ──────────────────────────────────────
    if (bitmapImg == null) return;
    final img     = bitmapImg!;
    final srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    // Plant render size — brinjal ~1.2m tall in real world
    final plantH  = (1.2 / mpp).clamp(18.0, 70.0);
    final aspect  = img.height / img.width;
    final plantW  = plantH / aspect;

    // Gentle wind sway
    final globalSway = sin(wind * pi * 2) * _speedN * 1.5 * _leanSign;

    // Sort back-to-front
    final sorted = List.of(plants)
      ..sort((a, b) => a.px.dy.compareTo(b.px.dy));

    for (final p in sorted) {
      final x = p.px.dx;
      final y = p.px.dy;

      if (x < b.left  - plantW || x > b.right  + plantW ||
          y < b.top   - plantH || y > b.bottom + plantH) continue;

      final depthFrac  = ((y - b.top) / (b.height + 1)).clamp(0.0, 1.0);
      final depthScale = 0.75 + depthFrac * 0.25;

      final dW    = plantW * depthScale;
      final dH    = plantH * depthScale;
      final swayX = globalSway * depthScale * (0.5 + p.p.phase * 0.3);
      final opacity = (0.82 + depthFrac * 0.18).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x + swayX, y);

      canvas.drawImageRect(img, srcRect,
          Rect.fromCenter(center: Offset(0, -dH * 0.48), width: dW, height: dH),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));

      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  VINEYARD RENDERER v6 — orchard-style, matches mango/horticulture quality
  //
  //  Satellite top-down view:
  //    • Warm brown soil with furrow stripes between rows
  //    • Each vine: gnarled trunk stub → wide green canopy dome
  //    • 4-6 dark blue-purple grape bunches hanging at canopy edge
  //    • Canopy has 3 concentric layers (shadow / mid / highlight)
  //    • Wind sway — gentle, phase-locked per plant
  //    • Staggered grid: every other row offset by half a vine gap
  //    • Depth scale: front rows slightly larger (perspective)
  //
  //  Real-world spacing:
  //    Row gap   : ~2.5 m  →  rowGap_px  = 2.5 / mpp
  //    Plant gap : ~1.5 m  →  plantGap_px = 1.5 / mpp
  // ═══════════════════════════════════════════════════════════════════════

  void _drawVineyard(Canvas canvas, Rect b, Size size, ui.Path clip, {bool heatmapActive = false}) {
    final vineGap  = (2.5 / mpp).clamp(32.0, 180.0);
    final canopyR  = (vineGap * 0.36).clamp(12.0, 55.0);
    final trunkR   = (canopyR * 0.14).clamp(2.0,  6.0);
    final bunchR   = (canopyR * 0.18).clamp(2.5,  9.0);

    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF4E342E);
    const soilLight = Color(0xFF795548);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Furrow stripes between rows ────────────────────────────────
    if (!heatmapActive) {
      final furrowPaint = Paint()
        ..color = const Color(0xFF3E2723).withOpacity(0.32)
        ..strokeWidth = vineGap * 0.26
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + vineGap * 0.5;
      while (fy < b.bottom + vineGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += vineGap;
      }
    }

    // ── 3. Trellis wires — one per row at mid-canopy height ──────────
    final wirePaint = Paint()
      ..color = const Color(0xFF8D6E63).withOpacity(0.45)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    // ── 4. Vines — staggered grid, back→front ────────────────────────
    var rowY = b.top + canopyR;
    var row  = 0;
    while (rowY <= b.bottom + canopyR) {
      final stagger  = (row % 2 == 0) ? 0.0 : vineGap * 0.5;
      final rowFrac  = ((rowY - b.top) / b.height.clamp(1.0, double.infinity)).clamp(0.0, 1.0);
      final depthScale = 0.84 + rowFrac * 0.18;

      // Trellis wire at arm height for this row
      canvas.drawLine(
        Offset(b.left, rowY - canopyR * 0.3 * depthScale),
        Offset(b.right, rowY - canopyR * 0.3 * depthScale),
        wirePaint,
      );

      var colX = b.left + stagger + canopyR * 0.5;
      var col  = 0;
      while (colX <= b.right + canopyR) {
        final seed    = Object.hash(row * 997 + col, 41);
        final rng     = Random(seed);
        final jx      = (rng.nextDouble() - 0.5) * vineGap * 0.10;
        final jy      = (rng.nextDouble() - 0.5) * vineGap * 0.10;
        final px      = colX + jx;
        final py      = rowY + jy;
        final variant = rng.nextInt(3);
        final sizeVar = 0.80 + variant * 0.12;
        final cr      = canopyR * sizeVar * depthScale;
        final phase   = rng.nextDouble() * pi * 2;

        // Wind sway — gentle, trellis-stabilised vines sway less than trees
        final swayX = sin(wind * pi * 2 + phase) * _leanSign *
                      (0.6 + _speedN * 1.2) * (cr / canopyR);

        _drawGrapeVine(
          canvas,
          pos: Offset(px, py),
          cr: cr,
          trunkR: trunkR * depthScale,
          bunchR: bunchR * depthScale,
          swayX: swayX,
          phase: phase,
          variant: variant,
          rowFrac: rowFrac,
        );

        colX += vineGap;
        col++;
      }
      rowY += vineGap * 0.90;
      row++;
    }
  }

  // ── Individual grape vine (top-down orchard view) ─────────────────────
  //
  //  Layer order back→front:
  //    1. Ground shadow ellipse
  //    2. Trunk stub (small oval at centre)
  //    3. Canopy — 3 concentric ovals (dark / mid / highlight)
  //    4. Grape bunches around canopy edge (deep indigo-purple)
  //    5. Leaf vein shimmer on canopy top

  void _drawGrapeVine(
    Canvas canvas, {
    required Offset pos,
    required double cr,       // canopy radius
    required double trunkR,
    required double bunchR,
    required double swayX,
    required double phase,
    required int variant,
    required double rowFrac,
  }) {
    final px = pos.dx;
    final py = pos.dy;

    // ── 1. Ground shadow ──────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.08 + cr * 0.06, py + cr * 0.30),
        width: cr * 1.90, height: cr * 0.55,
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cr * 0.20),
    );

    // ── 2. Trunk stub ─────────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.04, py + cr * 0.08),
        width:  trunkR * 2.4,
        height: trunkR * 1.6,
      ),
      Paint()..color = const Color(0xFF4E342E).withOpacity(0.92),
    );

    // ── 3. Canopy — 3 concentric layers ──────────────────────────────
    // Outermost: deep shadow inside canopy
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.35, py - cr * 0.04),
        width: cr * 2.05, height: cr * 1.80,
      ),
      Paint()..color = const Color(0xFF1B4A10).withOpacity(0.92),
    );

    // Mid layer: main foliage — rich vineyard green
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.50, py - cr * 0.10),
        width: cr * 1.68, height: cr * 1.48,
      ),
      Paint()..color = const Color(0xFF2E7D32).withOpacity(0.90),
    );

    // Inner highlight: sunlit canopy top
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.65 - cr * 0.16, py - cr * 0.26),
        width: cr * 0.96, height: cr * 0.76,
      ),
      Paint()..color = const Color(0xFF4CAF50).withOpacity(0.68),
    );

    // Top specular shimmer
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(px + swayX * 0.75 - cr * 0.26, py - cr * 0.40),
        width: cr * 0.42, height: cr * 0.30,
      ),
      Paint()..color = const Color(0xFF81C784).withOpacity(0.42),
    );

    // ── 4. Grape bunches around canopy edge ───────────────────────────
    if (cr > 8.0) {
      final bunchCount = 4 + variant; // 4–6 bunches per vine
      for (var bi = 0; bi < bunchCount; bi++) {
        // Distribute bunches around the lower 3/4 arc of the canopy
        final ang  = (bi / bunchCount.toDouble()) * pi * 1.6 + pi * 0.2 + phase * 0.15;
        final dist = cr * 0.68;
        final bx   = px + cos(ang) * dist + swayX * 0.65;
        final by   = py + sin(ang) * dist * 0.78 - cr * 0.04;
        final br   = bunchR * (0.78 + (bi % 3) * 0.12);

        // Bunch shadow
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(bx + br * 0.22, by + br * 0.28),
            width: br * 1.6, height: br * 2.2,
          ),
          Paint()..color = Colors.black.withOpacity(0.28),
        );

        // Bunch body — layered to simulate conical cluster shape
        // Top wide part
        canvas.drawOval(
          Rect.fromCenter(center: Offset(bx, by - br * 0.4),
              width: br * 1.55, height: br * 0.80),
          Paint()..color = const Color(0xFF1A237E).withOpacity(0.88),
        );
        // Mid body
        canvas.drawOval(
          Rect.fromCenter(center: Offset(bx, by + br * 0.4),
              width: br * 1.20, height: br * 1.30),
          Paint()..color = const Color(0xFF283593).withOpacity(0.82),
        );
        // Pointed tip
        canvas.drawOval(
          Rect.fromCenter(center: Offset(bx, by + br * 1.20),
              width: br * 0.60, height: br * 0.65),
          Paint()..color = const Color(0xFF3949AB).withOpacity(0.72),
        );

        // Berry highlight specks
        canvas.drawCircle(
          Offset(bx - br * 0.28, by - br * 0.55),
          br * 0.22,
          Paint()..color = const Color(0xFF5C6BC0).withOpacity(0.55),
        );
        canvas.drawCircle(
          Offset(bx + br * 0.20, by - br * 0.30),
          br * 0.18,
          Paint()..color = const Color(0xFF5C6BC0).withOpacity(0.45),
        );

        // Tiny stem to canopy
        canvas.drawLine(
          Offset(bx, by - br * 0.95),
          Offset(bx + (bx - px) * 0.12, by - br * 1.60),
          Paint()
            ..color = const Color(0xFF4E342E).withOpacity(0.65)
            ..strokeWidth = 0.8
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CABBAGE FIELD RENDERER — geo-locked grid layout
  //
  //  All sizes derived from mpp (metres per pixel) so the field stays
  //  perfectly stable when the user zooms in or out.
  //
  //  Real-world cabbage spacing:
  //    Row gap   : ~0.60 m  →  rowGap_px   = 0.60 / mpp
  //    Plant gap : ~0.55 m  →  plantGap_px = 0.55 / mpp
  //    Head size : ~0.22 m  →  headR_px    = 0.22 / mpp  (clamped 6–40 px)
  // ═══════════════════════════════════════════════════════════════════════

  void _drawCabbageField(Canvas canvas, Rect b, Size size, ui.Path clip, {bool heatmapActive = false}) {
    // ── Geo-locked dimensions (scale with zoom via mpp) ───────────────
    final rowGap   = (0.60 / mpp).clamp(18.0, 120.0);
    final plantGap = (0.55 / mpp).clamp(16.0, 110.0);
    final headR    = (0.22 / mpp).clamp(6.0,  40.0);
    // Jitter capped at 10% of plantGap so alignment is never broken
    final jitterMax = plantGap * 0.10;

    // ── 1. Soil background ────────────────────────────────────────────
    const Color soilDark  = Color(0xFF4E342E);
    const Color soilLight = Color(0xFF8D6E63);

    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
      ..shader = ui.Gradient.linear(
        Offset(b.left, b.top), Offset(b.left, b.bottom),
        [soilDark, soilLight],
      ));
    }

    // ── 2. Furrow shadow stripes — omitted when heatmap active ──────────
    if (!heatmapActive) {
      final furrowPaint = Paint()
        ..color = const Color(0xFF3E2723).withOpacity(0.30)
        ..style  = PaintingStyle.stroke
        ..strokeWidth = rowGap * 0.30
        ..strokeCap   = StrokeCap.butt;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    // ── 3. Cabbage heads in strict geo-locked grid ────────────────────
    var row = 0;
    var rowY = b.top + rowGap * 0.55;

    while (rowY < b.bottom + rowGap * 0.5) {
      final colOffset = (row % 2 == 0) ? 0.0 : plantGap * 0.5;
      var colX = b.left + plantGap * 0.4 + colOffset;
      final colIdx0 = (colX / plantGap).floor(); // stable index for hash

      while (colX < b.right + plantGap * 0.5) {
        final ci = (colX / plantGap).floor();
        // Deterministic jitter — same value every frame regardless of zoom
        final jx = ((row * 73  + ci * 37) % 11 - 5.0) / 5.0 * jitterMax;
        final jy = ((row * 53  + ci * 61) % 11 - 5.0) / 5.0 * jitterMax;
        final pos = Offset(colX + jx, rowY + jy);

        if (pos.dx > b.left - headR * 2 && pos.dx < b.right  + headR * 2 &&
            pos.dy > b.top  - headR * 2 && pos.dy < b.bottom + headR * 2) {
          // ±12% size variation — stable per plant
          final sizeVar    = 0.92 + ((row * 97 + ci * 43) % 12) / 100.0;
          // Depth scale: front rows slightly larger
          final depthScale = 0.93 + ((rowY - b.top) /
                             b.height.clamp(1.0, double.infinity)) * 0.08;
          // Gentle wind sway
          final sway = sin(wind * pi * 2 + pos.dx * 0.04 + pos.dy * 0.03) *
                       _leanSign * (0.6 + _speedN * 1.0);

          _drawCabbageHead(
            canvas, pos,
            radius: headR * sizeVar * depthScale,
            sway:   sway,
          );
        }
        colX += plantGap;
      }
      row++;
      rowY += rowGap;
    }
  }

  // ── Individual cabbage head ────────────────────────────────────────────
  //
  //  Layer order (back to front):
  //    1. Ground shadow (soft dark ellipse under head)
  //    2. Outer leaves — dark green, spread wide, overlap soil
  //    3. Mid leaves   — medium green, slightly smaller
  //    4. Inner leaves — pale yellow-green, compact dome
  //    5. Heart        — creamy white-yellow tight centre
  //    6. Leaf vein highlights on outer layers
  //    7. Rim light on top (gives volume / 3D feel)

  void _drawCabbageHead(Canvas canvas, Offset pos, {
    required double radius,
    required double sway,
  }) {
    final cx = pos.dx + sway * 0.4;
    final cy = pos.dy;

    // ── 1. Ground shadow ────────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 2, cy + radius * 0.55),
        width:  radius * 2.6,
        height: radius * 0.55,
      ),
      Paint()..color = Colors.black.withOpacity(0.22),
    );

    // ── 2. Outer leaves (3–4 splayed around base) ────────────────────
    const Color leafOuter = Color(0xFF2E7D32);  // dark green
    const Color leafMid   = Color(0xFF43A047);  // medium green
    const Color leafInner = Color(0xFF66BB6A);  // bright green
    const Color leafHeart = Color(0xFFC8E6C9);  // pale green-white
    const Color leafCore  = Color(0xFFF1F8E9);  // creamy white

    // Splayed outer leaves (4 directions)
    final outerPaint = Paint()
      ..color = leafOuter.withOpacity(0.92)
      ..style = PaintingStyle.fill;

    final List<Offset> outerTips = [
      Offset(cx - radius * 1.30 + sway, cy + radius * 0.25),
      Offset(cx + radius * 1.30 + sway, cy + radius * 0.25),
      Offset(cx + sway * 0.5,           cy + radius * 1.20),
      Offset(cx + sway * 0.3,           cy - radius * 0.50),
    ];

    for (final tip in outerTips) {
      final leafPath = ui.Path()
        ..moveTo(cx, cy)
        ..quadraticBezierTo(
          (cx + tip.dx) / 2 + (tip.dy - cy) * 0.15,
          (cy + tip.dy) / 2 - (tip.dx - cx) * 0.15,
          tip.dx, tip.dy,
        )
        ..quadraticBezierTo(
          (cx + tip.dx) / 2 - (tip.dy - cy) * 0.15,
          (cy + tip.dy) / 2 + (tip.dx - cx) * 0.15,
          cx, cy,
        );
      canvas.drawPath(leafPath, outerPaint);
    }

    // ── 3. Mid layer globe ───────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - radius * 0.08),
        width:  radius * 2.05,
        height: radius * 1.80,
      ),
      Paint()..color = leafMid.withOpacity(0.95),
    );

    // ── 4. Leaf texture on mid layer — curved stripe lines ───────────
    final veinPaint = Paint()
      ..color = leafOuter.withOpacity(0.28)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = -2; i <= 2; i++) {
      final startX = cx + i * radius * 0.35 + sway * 0.2;
      final ctrl1X = cx + i * radius * 0.20 + sway * 0.3;
      final ctrl2X = cx + i * radius * 0.45 + sway * 0.15;
      final veinPath = ui.Path()
        ..moveTo(startX, cy + radius * 0.75)
        ..cubicTo(
          ctrl1X, cy + radius * 0.30,
          ctrl2X, cy - radius * 0.20,
          cx + i * radius * 0.15 + sway * 0.1, cy - radius * 0.70,
        );
      canvas.drawPath(veinPath, veinPaint);
    }

    // ── 5. Inner compact dome ────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - radius * 0.18),
        width:  radius * 1.35,
        height: radius * 1.15,
      ),
      Paint()..color = leafInner.withOpacity(0.96),
    );

    // ── 6. Heart (pale tight centre) ─────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - radius * 0.28),
        width:  radius * 0.82,
        height: radius * 0.68,
      ),
      Paint()..color = leafHeart.withOpacity(0.97),
    );

    // ── 7. Core nub (creamy white tight point) ───────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - radius * 0.38),
        width:  radius * 0.38,
        height: radius * 0.30,
      ),
      Paint()..color = leafCore,
    );

    // ── 8. Rim light (top-left highlight — gives 3D sphere look) ────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - radius * 0.28, cy - radius * 0.52),
        width:  radius * 0.60,
        height: radius * 0.45,
      ),
      Paint()..color = const Color(0xFFE8F5E9).withOpacity(0.45),
    );

    // ── 9. Subtle dark edge shadow (lower rim — depth) ────────────────
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy - radius * 0.08),
        width:  radius * 2.05,
        height: radius * 1.80,
      ),
      0.3,   // start angle (radians)
      2.5,   // sweep angle
      false,
      Paint()
        ..color = leafOuter.withOpacity(0.30)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  MARIGOLD FIELD RENDERER — geo-locked row-based layout
  //
  //  Based on reference image:
  //    • Tall upright stems with pinnate feathery leaves
  //    • Dense ruffled orange/amber flower heads at the top
  //    • Planted in neat rows — soil visible between rows
  //    • Flowers are large, ball-shaped, richly layered petals
  //    • Warm reddish-brown soil (marigold fields in India)
  //
  //  All sizes scale with mpp for zoom stability:
  //    Row gap   : ~0.35 m  →  rowGap_px  = 0.35 / mpp
  //    Plant gap : ~0.30 m  →  plantGap_px= 0.30 / mpp
  //    Stem height: ~0.40 m →  stemH_px   = 0.40 / mpp  (clamped)
  //    Flower R  : ~0.12 m  →  flowerR_px = 0.12 / mpp  (clamped)
  // ═══════════════════════════════════════════════════════════════════════

  void _drawMarigoldField(Canvas canvas, Rect b, Size size, ui.Path clip, {bool heatmapActive = false}) {
    // ── Geo-locked dimensions ─────────────────────────────────────────
    final rowGap   = (0.35 / mpp).clamp(14.0, 100.0);
    final plantGap = (0.30 / mpp).clamp(12.0,  90.0);
    final stemH    = (0.40 / mpp).clamp(12.0,  90.0);
    final flowerR  = (0.12 / mpp).clamp( 5.0,  32.0);
    final jMax     = plantGap * 0.08; // ±8% micro-jitter

    // ── 1. Soil background — omitted when heatmap is active ─────────────
    if (!heatmapActive) {
      const Color soilDark  = Color(0xFF5D3A1A);
      const Color soilLight = Color(0xFF8B5E3C);
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Row furrow shadows ─────────────────────────────────────────
    final furrowPaint = Paint()
      ..color = const Color(0xFF3E200A).withOpacity(0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rowGap * 0.28
      ..strokeCap = StrokeCap.butt;

    var rowY = b.top + rowGap * 0.5;
    while (rowY < b.bottom + rowGap) {
      canvas.drawLine(Offset(b.left, rowY), Offset(b.right, rowY), furrowPaint);
      rowY += rowGap;
    }

    // ── 3. Plant marigolds — back rows first (painter's algorithm) ────
    // Collect all positions, sort front→back, draw back→front
    final List<_MarigoldPos> allPos = [];

    var row = 0;
    rowY = b.top + rowGap * 0.55;
    while (rowY < b.bottom + rowGap * 0.5) {
      final colOffset = (row % 2 == 0) ? 0.0 : plantGap * 0.5;
      var colX = b.left + plantGap * 0.35 + colOffset;
      final ci0 = (colX / plantGap).floor();

      while (colX < b.right + plantGap * 0.5) {
        final ci = (colX / plantGap).floor();
        final jx = ((row * 79 + ci * 41) % 17 - 8.0) / 8.0 * jMax;
        final jy = ((row * 61 + ci * 53) % 17 - 8.0) / 8.0 * jMax;
        final px = colX + jx;
        final py = rowY + jy;

        if (px > b.left - flowerR * 3 && px < b.right  + flowerR * 3 &&
            py > b.top  - flowerR * 3 && py < b.bottom + flowerR * 3) {
          // Size variation ±15%
          final sv = 0.88 + ((row * 89 + ci * 47) % 14) / 93.0;
          // Depth scale — front rows slightly taller
          final ds = 0.92 + ((py - b.top) / b.height.clamp(1.0, double.infinity)) * 0.10;
          // Bloom stage: some plants fully open, some budding (variety)
          final bloom = ((row * 67 + ci * 31) % 5) / 4.0; // 0=bud, 1=full bloom
          allPos.add(_MarigoldPos(Offset(px, py), sv * ds, bloom));
        }
        colX += plantGap;
      }
      row++;
      rowY += rowGap;
    }

    // Back-to-front draw (painter's algorithm — further rows drawn first)
    allPos.sort((a, b_) => a.pos.dy.compareTo(b_.pos.dy));

    for (final mp in allPos) {
      final sway = sin(wind * pi * 2 + mp.pos.dx * 0.04 + mp.pos.dy * 0.03) *
                   _leanSign * (0.8 + _speedN * 2.0);
      _drawMarigoldPlant(
        canvas, mp.pos,
        stemH:   stemH  * mp.scale,
        flowerR: flowerR * mp.scale,
        bloom:   mp.bloom,
        sway:    sway,
      );
    }
  }

  // ── Individual marigold plant ─────────────────────────────────────────
  //
  //  Layers (bottom to top):
  //    1. Ground shadow — soft dark ellipse under stem base
  //    2. Stem — thick green, slight curve with wind sway
  //    3. Pinnate leaves — pairs of small feathery leaflets along stem
  //    4. Flower shadow — dark ellipse under head
  //    5. Outer petal ring — deep amber/orange, wide ruffled ring
  //    6. Mid petal ring — bright orange, slightly raised
  //    7. Inner petals — golden-yellow dense centre dome
  //    8. Flower heart — dark orange-red tight nub
  //    9. Petal texture lines — thin strokes for ruffle depth

  void _drawMarigoldPlant(
    Canvas canvas, Offset pos, {
    required double stemH,
    required double flowerR,
    required double bloom,   // 0=tight bud  1=fully open
    required double sway,
  }) {
    final bx = pos.dx;
    final by = pos.dy;

    // ── 1. Ground shadow ─────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bx + 1.5, by + 1.5),
        width:  flowerR * 1.4,
        height: flowerR * 0.35,
      ),
      Paint()..color = Colors.black.withOpacity(0.20),
    );

    // ── 2. Stem ───────────────────────────────────────────────────────
    // Slight S-curve — base vertical, top bends with wind
    final stemTopX = bx + sway * 0.6;
    final stemTopY = by - stemH;
    final ctrl1X   = bx + sway * 0.2;
    final ctrl1Y   = by - stemH * 0.45;
    final ctrl2X   = bx + sway * 0.5;
    final ctrl2Y   = by - stemH * 0.75;

    final stemPath = ui.Path()
      ..moveTo(bx, by)
      ..cubicTo(ctrl1X, ctrl1Y, ctrl2X, ctrl2Y, stemTopX, stemTopY);

    canvas.drawPath(stemPath, Paint()
      ..color = const Color(0xFF2E7D32).withOpacity(0.95)
      ..strokeWidth = (stemH * 0.09).clamp(1.5, 5.0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // ── 3. Pinnate leaf pairs along stem ─────────────────────────────
    // 2–3 pairs of small compound leaves at 30/60% up the stem
    const leafColor = Color(0xFF388E3C);
    final leafPaint = Paint()
      ..color = leafColor.withOpacity(0.90)
      ..style = PaintingStyle.fill;

    for (var li = 0; li < 3; li++) {
      final t = 0.25 + li * 0.22; // fraction up stem
      final lx = bx + (stemTopX - bx) * t + (ctrl1X - bx) * t * (1 - t) * 2;
      final ly = by + (stemTopY - by) * t - stemH * t * (1 - t) * 0.3;
      final lSize = (stemH * 0.22).clamp(3.0, 14.0);
      final lSway = sway * t * 0.4;

      // Left leaflet
      final leftLeaf = ui.Path()
        ..moveTo(lx, ly)
        ..quadraticBezierTo(
          lx - lSize * 0.8 + lSway * 0.3, ly - lSize * 0.5,
          lx - lSize * 1.3 + lSway, ly - lSize * 0.1,
        )
        ..quadraticBezierTo(
          lx - lSize * 0.5 + lSway * 0.2, ly + lSize * 0.3,
          lx, ly,
        );
      canvas.drawPath(leftLeaf, leafPaint);

      // Right leaflet
      final rightLeaf = ui.Path()
        ..moveTo(lx, ly)
        ..quadraticBezierTo(
          lx + lSize * 0.8 + lSway * 0.3, ly - lSize * 0.5,
          lx + lSize * 1.3 + lSway, ly - lSize * 0.1,
        )
        ..quadraticBezierTo(
          lx + lSize * 0.5 + lSway * 0.2, ly + lSize * 0.3,
          lx, ly,
        );
      canvas.drawPath(rightLeaf, leafPaint);

      // Leaf vein
      canvas.drawLine(
        Offset(lx, ly),
        Offset(lx - lSize * 1.3 + lSway, ly - lSize * 0.1),
        Paint()
          ..color = const Color(0xFF1B5E20).withOpacity(0.40)
          ..strokeWidth = (lSize * 0.10).clamp(0.5, 1.5)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(lx, ly),
        Offset(lx + lSize * 1.3 + lSway, ly - lSize * 0.1),
        Paint()
          ..color = const Color(0xFF1B5E20).withOpacity(0.40)
          ..strokeWidth = (lSize * 0.10).clamp(0.5, 1.5)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Flower centre position
    final fx = stemTopX;
    final fy = stemTopY;

    // ── 4. Flower shadow ──────────────────────────────────────────────
    final openR = flowerR * (0.55 + bloom * 0.45); // bud=small, open=full
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(fx + openR * 0.3, fy + openR * 0.4),
        width:  openR * 2.4,
        height: openR * 0.6,
      ),
      Paint()..color = Colors.black.withOpacity(0.20),
    );

    // ── 5. Outer petal ring — deep amber ─────────────────────────────
    //    Ruffled outer ring drawn as many overlapping petal shapes
    final int petalCount = (8 + (bloom * 6).round()).clamp(8, 16);
    const Color outerPetal = Color(0xFFE65100);  // deep orange
    const Color midPetal   = Color(0xFFFF8F00);  // bright amber
    const Color innerPetal = Color(0xFFFFCA28);  // golden yellow
    const Color heartColor = Color(0xFFBF360C);  // dark orange-red centre

    // Outer ruffled petals
    for (var pi = 0; pi < petalCount; pi++) {
      final angle = (pi / petalCount) * pi * 2;
      final petalX = fx + cos(angle) * openR * 0.85 + sway * 0.15;
      final petalY = fy + sin(angle) * openR * 0.85 * 0.80;
      final ctrlX  = fx + cos(angle) * openR * 1.45 + sway * 0.20;
      final ctrlY  = fy + sin(angle) * openR * 1.35 * 0.80;

      final petal = ui.Path()
        ..moveTo(fx + sway * 0.05, fy)
        ..quadraticBezierTo(
          ctrlX - sin(angle) * openR * 0.35,
          ctrlY + cos(angle) * openR * 0.25,
          petalX, petalY,
        )
        ..quadraticBezierTo(
          ctrlX + sin(angle) * openR * 0.35,
          ctrlY - cos(angle) * openR * 0.25,
          fx + sway * 0.05, fy,
        );

      canvas.drawPath(petal, Paint()
        ..color = outerPetal.withOpacity(0.88)
        ..style = PaintingStyle.fill);
      // Petal edge highlight
      canvas.drawPath(petal, Paint()
        ..color = const Color(0xFFFF6D00).withOpacity(0.35)
        ..strokeWidth = (openR * 0.08).clamp(0.5, 2.0)
        ..style = PaintingStyle.stroke);
    }

    // ── 6. Mid petal ring — bright orange ─────────────────────────────
    final int midCount = (7 + (bloom * 5).round()).clamp(7, 14);
    final midR = openR * 0.72;
    for (var pi = 0; pi < midCount; pi++) {
      final angle = (pi / midCount) * pi * 2 + pi / midCount * 0.5;
      final petalX = fx + cos(angle) * midR * 0.82 + sway * 0.10;
      final petalY = fy + sin(angle) * midR * 0.82 * 0.80;
      final ctrlX  = fx + cos(angle) * midR * 1.35 + sway * 0.12;
      final ctrlY  = fy + sin(angle) * midR * 1.25 * 0.80;

      final petal = ui.Path()
        ..moveTo(fx + sway * 0.03, fy)
        ..quadraticBezierTo(
          ctrlX - sin(angle) * midR * 0.30,
          ctrlY + cos(angle) * midR * 0.20,
          petalX, petalY,
        )
        ..quadraticBezierTo(
          ctrlX + sin(angle) * midR * 0.30,
          ctrlY - cos(angle) * midR * 0.20,
          fx + sway * 0.03, fy,
        );
      canvas.drawPath(petal, Paint()
        ..color = midPetal.withOpacity(0.92)
        ..style = PaintingStyle.fill);
    }

    // ── 7. Inner petal dome — golden yellow ────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(fx + sway * 0.05, fy - openR * 0.10),
        width:  openR * 1.10,
        height: openR * 0.95,
      ),
      Paint()..color = innerPetal.withOpacity(0.96),
    );

    // ── 8. Tight centre nub — dark orange-red ─────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(fx + sway * 0.03, fy - openR * 0.14),
        width:  openR * 0.52,
        height: openR * 0.44,
      ),
      Paint()..color = heartColor.withOpacity(0.95),
    );

    // ── 9. Rim highlight — top-left light catch ────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(fx - openR * 0.28 + sway * 0.05, fy - openR * 0.42),
        width:  openR * 0.55,
        height: openR * 0.38,
      ),
      Paint()..color = const Color(0xFFFFE082).withOpacity(0.45),
    );

    // ── 10. Petal texture strokes (ruffle lines) ──────────────────────
    if (openR > 8.0) {
      final texturePaint = Paint()
        ..color = outerPetal.withOpacity(0.30)
        ..strokeWidth = (openR * 0.055).clamp(0.5, 1.5)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (var ti = 0; ti < 8; ti++) {
        final a = (ti / 8.0) * pi * 2;
        canvas.drawLine(
          Offset(fx + cos(a) * openR * 0.40 + sway * 0.04,
                 fy + sin(a) * openR * 0.34),
          Offset(fx + cos(a) * openR * 1.05 + sway * 0.12,
                 fy + sin(a) * openR * 0.88),
          texturePaint,
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SESAME / TIL FIELD RENDERER — dense upright natural-grass look
  //
  //  Sesame (Sesamum indicum) in a real field:
  //    • Grows 0.9–1.8 m tall — tall upright stalks, like dense grass
  //    • Very dense planting — stalks close together in rows
  //    • Narrow lance-shaped opposite leaves at regular nodes
  //    • Small white/pale-purple tubular bell flowers along upper stalk
  //    • From aerial/map view: looks like a dense green grass carpet
  //      with visible row structure and light sandy-brown soil between rows
  //    • Painter's-algorithm rows: front taller, back shorter (perspective)
  //
  //  Geo-locked sizing (all via mpp):
  //    Row gap     : 0.30 m  →  (0.30 / mpp)  clamped 10–80 px
  //    Stalk gap   : 0.10 m  →  (0.10 / mpp)  clamped  4–28 px  (very dense)
  //    Stalk height: 0.90 m  →  (0.90 / mpp)  clamped 18–120 px
  // ═══════════════════════════════════════════════════════════════════════

  void _drawSesameField(Canvas canvas, Rect b, Size size, ui.Path clip, {bool heatmapActive = false}) {
    // ── Geo-locked dimensions ─────────────────────────────────────────
    final rowGap    = (0.30 / mpp).clamp(10.0, 80.0);
    final stalkGap  = (0.10 / mpp).clamp( 4.0, 28.0);
    final stalkH    = (0.90 / mpp).clamp(18.0, 120.0);
    final leafSize  = (stalkH * 0.18).clamp(2.5, 16.0);
    final flowerR   = (stalkH * 0.08).clamp(1.5,  8.0);

    // ── 1. Soil background — dry sandy brown — omitted when heatmap active
    const Color soilDark  = Color(0xFF6D4C2A);
    const Color soilLight = Color(0xFF9C7A52);

    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Subtle row furrow lines ────────────────────────────────────
    final furrowPaint = Paint()
      ..color = const Color(0xFF4A3010).withOpacity(0.22)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = rowGap * 0.20
      ..strokeCap   = StrokeCap.butt;

    var fy = b.top + rowGap * 0.5;
    while (fy < b.bottom + rowGap) {
      canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
      fy += rowGap;
    }

    // ── 3. Draw rows back→front (painter's algorithm) ─────────────────
    // Collect row Y positions, process from top (back) to bottom (front)
    final List<double> rowYs = [];
    var rowY = b.top + rowGap * 0.55;
    while (rowY < b.bottom + rowGap * 0.5) {
      rowYs.add(rowY);
      rowY += rowGap;
    }

    for (var ri = 0; ri < rowYs.length; ri++) {
      final ry = rowYs[ri];
      // Depth fraction: 0=back(top) → 1=front(bottom)
      final depthFrac = rowYs.isEmpty
          ? 0.5
          : ri / (rowYs.length - 1).clamp(1, 9999);
      // Front rows slightly taller and brighter (perspective depth)
      final heightScale = 0.88 + depthFrac * 0.16;
      final brightnessShift = depthFrac * 0.10;

      // Column stagger alternating rows
      final staggerX = (ri % 2 == 0) ? 0.0 : stalkGap * 0.5;
      var cx = b.left + stalkGap * 0.3 + staggerX;

      while (cx < b.right + stalkGap * 0.5) {
        // Deterministic per-stalk variation
        final si = (cx / stalkGap).floor();
        final hVar = 0.82 + ((ri * 83 + si * 47) % 19) / 95.0;
        final thisH = stalkH * heightScale * hVar;

        // Very subtle jitter (≤6% of stalkGap) — keeps the grass-dense look
        final jx = ((ri * 71 + si * 43) % 13 - 6.0) / 6.0 * stalkGap * 0.06;
        final jy = ((ri * 59 + si * 31) % 13 - 6.0) / 6.0 * stalkGap * 0.04;

        _drawSesameStem(
          canvas,
          base: Offset(cx + jx, ry + jy),
          height: thisH,
          leafSz: leafSize * hVar,
          flowerR: flowerR * hVar,
          wind: wind,
          speedN: _speedN,
          leanSign: _leanSign,
          brightShift: brightnessShift,
          rowIdx: ri,
          colIdx: si,
        );

        cx += stalkGap;
      }
    }
  }

  // ── Individual sesame stalk ───────────────────────────────────────────
  //
  //  Visual anatomy (bottom to top):
  //    1. Stem base root — tiny brown nub
  //    2. Main upright stalk — thin green line with cubic wind sway
  //    3. Opposite leaf pairs at ~35%, 55%, 70% up stalk — lance-shaped
  //    4. Upper stem with flower buds — small tubular bells at nodes
  //    5. Tip — slight droop with a terminal flower/bud
  //
  //  The dense cluster of many stalks side by side creates the
  //  "natural tall grass" look seen from above.

  void _drawSesameStem(
    Canvas canvas, {
    required Offset base,
    required double height,
    required double leafSz,
    required double flowerR,
    required double wind,
    required double speedN,
    required double leanSign,
    required double brightShift,
    required int rowIdx,
    required int colIdx,
  }) {
    // Wind sway — moderate, sesame sways naturally in breeze
    final phase = (rowIdx * 0.37 + colIdx * 0.61) % (pi * 2);
    final swayAmp = height * (0.04 + speedN * 0.06);
    final swayX = sin(wind * pi * 2 + phase) * leanSign * swayAmp;
    // Slight lean variation per stalk (natural field look)
    final leanX = (((rowIdx * 53 + colIdx * 29) % 11) - 5.0) * height * 0.010;

    final tipX = base.dx + swayX + leanX;
    final tipY = base.dy - height;

    // Control points for natural S-curve stalk
    final c1x = base.dx + swayX * 0.20 + leanX * 0.30;
    final c1y = base.dy - height * 0.40;
    final c2x = base.dx + swayX * 0.65 + leanX * 0.70;
    final c2y = base.dy - height * 0.72;

    // ── Stalk color: medium green, slightly darker at base ───────────
    final stalkGreen = Color.lerp(
      const Color(0xFF2E7D32),
      const Color(0xFF558B2F),
      0.3 + brightShift,
    )!;
    final stalkW = (height * 0.045).clamp(0.8, 3.0);

    final stalkPath = ui.Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(c1x, c1y, c2x, c2y, tipX, tipY);

    canvas.drawPath(stalkPath, Paint()
      ..color = stalkGreen.withOpacity(0.92)
      ..strokeWidth = stalkW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // ── Opposite leaf pairs at 3 nodes ───────────────────────────────
    // Only draw if stalk is tall enough to show detail
    if (height > 14.0 && leafSz > 2.0) {
      final leafPaint = Paint()
        ..color = const Color(0xFF388E3C).withOpacity(0.88 + brightShift * 0.1)
        ..style = PaintingStyle.fill;

      for (var ni = 0; ni < 3; ni++) {
        final t = 0.30 + ni * 0.18;
        // Point on cubic bezier at parameter t
        final mt = 1 - t;
        final nx = mt * mt * mt * base.dx
            + 3 * mt * mt * t * c1x
            + 3 * mt * t * t * c2x
            + t * t * t * tipX;
        final ny = mt * mt * mt * base.dy
            + 3 * mt * mt * t * c1y
            + 3 * mt * t * t * c2y
            + t * t * t * tipY;

        // Tangent direction at t for leaf perpendicular angle
        final dtx = 3 * (mt * mt * (c1x - base.dx)
            + 2 * mt * t * (c2x - c1x)
            + t * t * (tipX - c2x));
        final dty = 3 * (mt * mt * (c1y - base.dy)
            + 2 * mt * t * (c2y - c1y)
            + t * t * (tipY - c2y));
        final len = sqrt(dtx * dtx + dty * dty).clamp(0.001, 9999.0);
        // Perpendicular = (-dty/len, dtx/len)
        final px = -dty / len;
        final py =  dtx / len;

        final lScale = (1.0 - ni * 0.12);
        final lSz = leafSz * lScale;
        final swayInfluence = swayX * t * 0.3;

        // Left leaf — lance shape (pointed tip)
        for (final side in [-1.0, 1.0]) {
          final lbx = nx + side * stalkW * 0.5;
          final lby = ny;
          final ltx = nx + side * px * lSz * 1.4 + swayInfluence;
          final lty = ny + side * py * lSz * 1.4 - lSz * 0.25;

          final leaf = ui.Path()
            ..moveTo(lbx, lby)
            ..quadraticBezierTo(
              lbx + side * px * lSz * 0.8 + swayInfluence * 0.5,
              lby + side * py * lSz * 0.8 - lSz * 0.1,
              ltx, lty,
            )
            ..quadraticBezierTo(
              lbx + side * px * lSz * 0.3 + swayInfluence * 0.2,
              lby + side * py * lSz * 0.3 + lSz * 0.05,
              lbx, lby,
            );
          canvas.drawPath(leaf, leafPaint);

          // Leaf midrib vein
          if (lSz > 4.0) {
            canvas.drawLine(
              Offset(lbx, lby),
              Offset(ltx * 0.85 + lbx * 0.15, lty * 0.85 + lby * 0.15),
              Paint()
                ..color = const Color(0xFF1B5E20).withOpacity(0.35)
                ..strokeWidth = (stalkW * 0.45).clamp(0.4, 1.2)
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      }
    }

    // ── Flower buds / bells along upper stalk ────────────────────────
    // Sesame has white/pale-purple tubular flowers at leaf axils
    if (height > 18.0 && flowerR > 1.5) {
      // 2–3 flowers along upper 30% of stalk
      for (var fi = 0; fi < 3; fi++) {
        final t = 0.68 + fi * 0.10;
        if (t > 1.0) continue;
        final mt2 = 1 - t;
        final fx = mt2 * mt2 * mt2 * base.dx
            + 3 * mt2 * mt2 * t * c1x
            + 3 * mt2 * t * t * c2x
            + t * t * t * tipX;
        final fyC = mt2 * mt2 * mt2 * base.dy
            + 3 * mt2 * mt2 * t * c1y
            + 3 * mt2 * t * t * c2y
            + t * t * t * tipY;

        // Alternate sides — sesame flowers grow in leaf axils both sides
        final side = (fi % 2 == 0) ? -1.0 : 1.0;
        final fOffX = side * flowerR * 1.2 + swayX * t * 0.2;
        final fOffY = -flowerR * 0.5;

        // White tubular bell (outer calyx)
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(fx + fOffX, fyC + fOffY),
            width:  flowerR * 1.6,
            height: flowerR * 2.2,
          ),
          Paint()..color = const Color(0xFFE8EAF6).withOpacity(0.90),
        );
        // Pale purple inner tube
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(fx + fOffX, fyC + fOffY - flowerR * 0.2),
            width:  flowerR * 0.85,
            height: flowerR * 1.10,
          ),
          Paint()..color = const Color(0xFFCE93D8).withOpacity(0.80),
        );
        // Green calyx base
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(fx + fOffX, fyC + fOffY + flowerR * 0.75),
            width:  flowerR * 1.1,
            height: flowerR * 0.65,
          ),
          Paint()..color = const Color(0xFF388E3C).withOpacity(0.85),
        );
      }
    }

    // ── Tip — terminal bud or slight droop ───────────────────────────
    if (height > 12.0) {
      // Tiny terminal bud at very tip
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(tipX, tipY - flowerR * 0.4),
          width:  flowerR * 1.0,
          height: flowerR * 1.5,
        ),
        Paint()..color = const Color(0xFF81C784).withOpacity(0.85),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  MANGO ORCHARD RENDERER
  //
  //  Satellite-view appearance:
  //    • Large individual trees clearly spaced apart (~6–8 m)
  //    • Staggered grid planting (offset every other row)
  //    • Each tree: thick trunk stub + 3-layer round canopy with depth
  //    • Deep circular shadow under each canopy
  //    • Bright yellow-orange mango fruits visible at canopy edges
  //    • Soil furrows visible between trees
  //    • Very gentle wind sway — large trees barely move
  // ═══════════════════════════════════════════════════════════════════════

  // ── Seedling field — dense grid of seedling images with gentle sway ──────
  void _drawSeedlingField(Canvas canvas, Rect bounds, ui.Path clip) {
    if (seedlingImg == null) return;

    canvas.save();
    canvas.clipPath(clip);

    // Soil background — warm dark earth for fresh planting
    canvas.drawPath(clip, Paint()
      ..color = const Color(0xFF4A3020).withOpacity(0.75));

    final img = seedlingImg!;
    final srcRect = Rect.fromLTWH(0, 0,
        img.width.toDouble(), img.height.toDouble());

    // Each seedling is small — scale based on mpp
    final plantH = (0.22 / mpp).clamp(12.0, 40.0);
    final aspect = img.height / img.width;
    final plantW = plantH / aspect;

    // Wind sway
    final sway = sin(wind * pi * 2) * _speedN * 3.5 * _leanSign;

    for (final p in plants) {
      final x = p.px.dx;
      final y = p.px.dy;

      // Skip if outside clipped bounds (saves paint calls)
      if (x < bounds.left - plantW || x > bounds.right + plantW ||
          y < bounds.top  - plantH || y > bounds.bottom + plantH) continue;

      final opacity = (0.80 + sin(wind * pi * 2 + p.p.phase * pi) * 0.12)
          .clamp(0.6, 1.0);

      canvas.save();
      // Pivot sway at base of plant
      canvas.translate(x, y);
      canvas.translate(sway * (1.0 - p.p.rowFrac * 0.3), 0);

      final dstRect = Rect.fromCenter(
        center: Offset(0, -plantH * 0.5),
        width:  plantW,
        height: plantH,
      );

      canvas.drawImageRect(img, srcRect, dstRect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));

      canvas.restore();
    }

    canvas.restore();

    // Fresh green border glow
    canvas.drawPath(clip, Paint()
      ..color = const Color(0xFF76FF03).withOpacity(0.60)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke);
  }

  // ── Mango bitmap orchard — stamps the provided tree image across the field
  void _drawMangoBitmapOrchard(Canvas canvas, Rect bounds, ui.Path clip) {
    final img = bitmapImg!;
    final srcRect = Rect.fromLTWH(0, 0,
        img.width.toDouble(), img.height.toDouble());

    // Tree size: mango trees are large — 6m spacing, proportional render
    final treeH = (5.5 / mpp).clamp(28.0, 90.0);
    final aspect = img.height / img.width;
    final treeW = treeH / aspect;

    // Stagger alternate rows for a natural orchard look
    final sway = sin(wind * pi * 2) * _speedN * 2.5 * _leanSign;

    // Sort plants back-to-front (higher y = closer = draw last on top)
    final sorted = List.of(plants)
      ..sort((a, b) => a.px.dy.compareTo(b.px.dy));

    for (final p in sorted) {
      final x = p.px.dx;
      final y = p.px.dy;

      if (x < bounds.left - treeW  || x > bounds.right  + treeW ||
          y < bounds.top  - treeH  || y > bounds.bottom + treeH) continue;

      // Depth scaling — trees further back (smaller y) are slightly smaller
      final depthFrac = ((y - bounds.top) / (bounds.height + 1)).clamp(0.0, 1.0);
      final depthScale = 0.72 + depthFrac * 0.28;

      final dW = treeW * depthScale;
      final dH = treeH * depthScale;

      // Wind sway — pivot at base of trunk
      final trunkY = y - dH * 0.08; // base of tree
      final swayX  = sway * depthScale * 0.6;

      // Slight opacity variation for depth
      final opacity = (0.78 + depthFrac * 0.22).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(x + swayX, trunkY);

      final dstRect = Rect.fromCenter(
        center: Offset(0, -dH * 0.50),
        width: dW,
        height: dH,
      );

      canvas.drawImageRect(img, srcRect, dstRect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, opacity));

      canvas.restore();
    }
  }

  void _drawMangoOrchard(Canvas canvas, Rect b, Size size, ui.Path clip,
      {bool heatmapActive = false}) {

    // Geo-locked tree spacing — mango trees ~6m apart
    final treeGap  = (6.0 / mpp).clamp(36.0, 160.0);
    final canopyR  = (treeGap * 0.38).clamp(14.0, 58.0);
    final trunkR   = (canopyR * 0.12).clamp(2.0, 7.0);
    final fruitR   = (canopyR * 0.10).clamp(2.0, 6.0);

    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF4E2A10);
    const soilLight = Color(0xFF7A4A25);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));
    }

    // ── 2. Trees — staggered grid top→bottom ──────────────────────────
    var rowY = b.top + canopyR;
    var row  = 0;
    while (rowY <= b.bottom + canopyR) {
      // Stagger every other row by half a tree-gap
      final stagger = (row % 2 == 0) ? 0.0 : treeGap * 0.5;
      final rowFrac = ((rowY - b.top) / b.height.clamp(1.0, double.infinity))
          .clamp(0.0, 1.0);
      final depthScale = 0.88 + rowFrac * 0.14;

      var colX = b.left + stagger + canopyR * 0.5;
      var col  = 0;
      while (colX <= b.right + canopyR) {
        // Deterministic per-tree variation
        final seed    = Object.hash(row * 997 + col, 13);
        final rng     = Random(seed);
        final jx      = (rng.nextDouble() - 0.5) * treeGap * 0.12;
        final jy      = (rng.nextDouble() - 0.5) * treeGap * 0.12;
        final px      = colX + jx;
        final py      = rowY + jy;
        final variant = rng.nextInt(3); // 0=small, 1=medium, 2=large
        final sizeVar = 0.80 + variant * 0.12;
        final cr      = canopyR * sizeVar * depthScale;

        // Wind sway — very gentle for large trees
        final phase  = rng.nextDouble() * pi * 2;
        final swayX  = sin(wind * pi * 2 + phase) * _leanSign *
                       (0.8 + _speedN * 1.5) * (cr / canopyR);

        // ── Ground shadow (ellipse below canopy) ──────────────────
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.1 + cr * 0.08,
                           py + cr * 0.35),
            width:  cr * 2.0,
            height: cr * 0.65,
          ),
          Paint()
            ..color = Colors.black.withOpacity(0.38)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cr * 0.25),
        );

        // ── Trunk stub ────────────────────────────────────────────
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.05, py + cr * 0.10),
            width:  trunkR * 2.2,
            height: trunkR * 1.4,
          ),
          Paint()..color = const Color(0xFF5D3A1A).withOpacity(0.90),
        );

        // ── Canopy — 3 concentric layers ──────────────────────────
        // Outermost: darkest (deep shadow inside canopy)
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.4, py - cr * 0.05),
            width: cr * 2.1, height: cr * 1.85,
          ),
          Paint()..color = const Color(0xFF1A4A0A).withOpacity(0.90),
        );

        // Mid layer: main foliage colour
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.55, py - cr * 0.10),
            width: cr * 1.72, height: cr * 1.52,
          ),
          Paint()..color = const Color(0xFF2D6E18).withOpacity(0.88),
        );

        // Inner highlight: sunlit canopy top
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.70 - cr * 0.18,
                           py - cr * 0.28),
            width: cr * 1.00, height: cr * 0.80,
          ),
          Paint()..color = const Color(0xFF4A9020).withOpacity(0.72),
        );

        // Top specular highlight (sun reflection)
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.80 - cr * 0.28,
                           py - cr * 0.42),
            width: cr * 0.44, height: cr * 0.32,
          ),
          Paint()..color = const Color(0xFF82C840).withOpacity(0.45),
        );

        // ── Mango fruits at canopy edge ───────────────────────────
        // Only draw fruits when tree is large enough to see them
        if (cr > 10.0) {
          final fruitCount = 3 + variant; // 3–5 fruits per tree
          for (var fi = 0; fi < fruitCount; fi++) {
            final ang   = (fi / fruitCount.toDouble()) * pi * 2 +
                          phase * 0.3 + swayX * 0.02;
            final dist  = cr * 0.72;
            final fx    = px + cos(ang) * dist + swayX * 0.6;
            final fy    = py + sin(ang) * dist * 0.72 - cr * 0.08;

            // Fruit shadow
            canvas.drawCircle(
              Offset(fx + fruitR * 0.3, fy + fruitR * 0.3),
              fruitR * 0.80,
              Paint()..color = Colors.black.withOpacity(0.22),
            );

            // Fruit body — yellow-orange gradient
            final fruitColor = Color.lerp(
              const Color(0xFFFFB300), // golden yellow
              const Color(0xFFFF6D00), // orange-red
              (fi / fruitCount.toDouble()),
            )!;
            canvas.drawCircle(
              Offset(fx, fy),
              fruitR * depthScale,
              Paint()..color = fruitColor.withOpacity(0.90),
            );

            // Fruit highlight
            canvas.drawCircle(
              Offset(fx - fruitR * 0.30, fy - fruitR * 0.28),
              fruitR * 0.28,
              Paint()..color = Colors.white.withOpacity(0.50),
            );

            // Tiny stem
            canvas.drawLine(
              Offset(fx, fy - fruitR * 0.88),
              Offset(fx + fruitR * 0.15, fy - fruitR * 1.35),
              Paint()
                ..color = const Color(0xFF4A7A20).withOpacity(0.80)
                ..strokeWidth = fruitR * 0.25
                ..strokeCap = StrokeCap.round,
            );
          }
        }

        colX += treeGap;
        col++;
      }
      rowY += treeGap * 0.88; // slightly tighter row spacing than column
      row++;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TOMATO FIELD RENDERER
  //
  //  Satellite-view appearance:
  //    • Horizontal rows of bushy dark-green canopy clusters
  //    • Brown soil furrows clearly visible between rows
  //    • Bright red/orange tomato fruit clusters dotting the canopy
  //    • Wind sways foliage gently
  //    • Fruit clusters pulse slightly with the rustle animation
  //
  //  Real-world spacing:
  //    Row gap   : ~0.75 m  →  rowGap_px = 0.75 / mpp
  //    Plant gap : ~0.50 m  →  plantGap_px = 0.50 / mpp
  // ═══════════════════════════════════════════════════════════════════════

  void _drawTomatoField(Canvas canvas, Rect b, Size size, ui.Path clip,
      {bool heatmapActive = false}) {

    final rowGap   = (0.75 / mpp).clamp(20.0, 90.0);
    final plantGap = (0.50 / mpp).clamp(14.0, 60.0);
    final bushR    = (plantGap * 0.42).clamp(5.0, 22.0);  // bush radius
    final fruitR   = (bushR * 0.28).clamp(2.0, 8.0);      // tomato radius

    // ── 1. Soil background ─────────────────────────────────────────────
    const soilDark  = Color(0xFF4A3020);
    const soilLight = Color(0xFF7A5035);
    if (!heatmapActive) {
      canvas.drawPath(clip, Paint()..color = soilDark);
      canvas.drawPath(clip, Paint()
        ..shader = ui.Gradient.linear(
          Offset(b.left, b.top), Offset(b.left, b.bottom),
          [soilDark, soilLight],
        ));

      // Furrow lines between rows
      final furrowPaint = Paint()
        ..color = const Color(0xFF2E1A0A).withOpacity(0.30)
        ..strokeWidth = rowGap * 0.28
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      var fy = b.top + rowGap * 0.5;
      while (fy < b.bottom + rowGap) {
        canvas.drawLine(Offset(b.left, fy), Offset(b.right, fy), furrowPaint);
        fy += rowGap;
      }
    }

    // ── 2. Tomato plants — row by row top→bottom ───────────────────────
    var rowY = b.top + rowGap * 0.55;
    var row  = 0;
    while (rowY <= b.bottom + rowGap) {
      final rowFrac  = ((rowY - b.top) / b.height.clamp(1.0, double.infinity)).clamp(0.0, 1.0);
      final depthScale = 0.90 + rowFrac * 0.12;  // front rows slightly larger
      final stagger  = (row % 2 == 0) ? 0.0 : plantGap * 0.5;

      var colX = b.left + stagger + plantGap * 0.5;
      var col  = 0;
      while (colX <= b.right + plantGap) {
        // Deterministic jitter per plant
        final jx = ((col * 1453 + row * 179) % 13 - 6.0) * 0.55;
        final jy = ((col * 997  + row *  83) % 11 - 5.0) * 0.45;
        final px = colX + jx;
        final py = rowY + jy;

        // Wind sway on foliage
        final phase  = ((col * 0.37 + row * 0.61) % (pi * 2));
        final swayX  = sin(wind * pi * 2 + phase) * _leanSign *
                       (1.5 + _speedN * 3.0);

        final br = bushR * depthScale;
        final fr = fruitR * depthScale;

        // ── Bush shadow ──────────────────────────────────────────────
        canvas.drawCircle(
          Offset(px + br * 0.15 + swayX * 0.1, py + br * 0.18),
          br * 0.95,
          Paint()..color = Colors.black.withOpacity(0.22),
        );

        // ── Main canopy — layered ovals for depth ────────────────────
        // Back layer (darker)
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.3, py),
            width: br * 2.2, height: br * 1.6,
          ),
          Paint()..color = const Color(0xFF1B5E20).withOpacity(0.88),
        );
        // Mid layer
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.5, py - br * 0.15),
            width: br * 1.8, height: br * 1.35,
          ),
          Paint()..color = const Color(0xFF2E7D32).withOpacity(0.85),
        );
        // Top highlight
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px + swayX * 0.65 - br * 0.2, py - br * 0.3),
            width: br * 1.0, height: br * 0.7,
          ),
          Paint()..color = const Color(0xFF43A047).withOpacity(0.55),
        );

        // ── Tomato fruit clusters (2–3 per plant) ────────────────────
        final fruitCount = 2 + (col + row) % 2; // 2 or 3 fruits
        for (var fi = 0; fi < fruitCount; fi++) {
          final fAngle = (fi / fruitCount.toDouble()) * pi * 1.6 - 0.3;
          final fDist  = br * 0.55;
          final fx = px + cos(fAngle) * fDist + swayX * 0.7;
          final fy2 = py + sin(fAngle) * fDist * 0.5 - br * 0.1;

          // Fruit shadow
          canvas.drawCircle(
            Offset(fx + fr * 0.2, fy2 + fr * 0.25),
            fr * 0.85,
            Paint()..color = Colors.black.withOpacity(0.20),
          );

          // Fruit — bright red with orange highlight
          final fruitColor = Color.lerp(
            const Color(0xFFE53935),
            const Color(0xFFFF7043),
            (fi / fruitCount.toDouble()),
          )!;
          canvas.drawCircle(
            Offset(fx, fy2),
            fr,
            Paint()..color = fruitColor.withOpacity(0.92 * depthScale),
          );

          // Highlight spot on fruit
          canvas.drawCircle(
            Offset(fx - fr * 0.28, fy2 - fr * 0.28),
            fr * 0.30,
            Paint()..color = Colors.white.withOpacity(0.45),
          );

          // Tiny green calyx star on top of fruit
          canvas.drawCircle(
            Offset(fx, fy2 - fr * 0.78),
            fr * 0.22,
            Paint()..color = const Color(0xFF388E3C).withOpacity(0.80),
          );
        }

        colX += plantGap;
        col++;
      }
      rowY += rowGap;
      row++;
    }
  }

  // ─── Soil base ────────────────────────────────────────────────────────

  void _drawSoil(Canvas canvas, Rect b, ui.Path clip) {
    // Realistic farmland soil colors — brown palette, NO green overlay
    Color c1, c2;
    switch (family) {
      case CropFamily.rice:
        // Wet paddy field — dark muddy brown
        c1 = const Color(0xFF4A3728); c2 = const Color(0xFF6B4F38); break;
      case CropFamily.wheat:
      case CropFamily.mustard:
        // Dry tilled soil — medium brown
        c1 = const Color(0xFF5D4037); c2 = const Color(0xFF8D6E63); break;
      case CropFamily.tree:
        // Orchard soil — rich dark brown
        c1 = const Color(0xFF4E342E); c2 = const Color(0xFF795548); break;
      case CropFamily.corn:
        // Maize field — warm brown tilled soil
        c1 = const Color(0xFF6D4C41); c2 = const Color(0xFFA1887F); break;
      case CropFamily.grape:
        // Vineyard — classic terracotta-brown soil
        c1 = const Color(0xFF5D4037); c2 = const Color(0xFFA1887F); break;
      case CropFamily.cabbage:
        // Cabbage field — rich moist dark brown
        c1 = const Color(0xFF4E342E); c2 = const Color(0xFF8D6E63); break;
      case CropFamily.marigold:
        // Marigold field — warm reddish-brown soil
        c1 = const Color(0xFF5D3A1A); c2 = const Color(0xFF8B5E3C); break;
      case CropFamily.sesame:
        // Sesame field — dry sandy-brown soil (dryland crop)
        c1 = const Color(0xFF6D4C2A); c2 = const Color(0xFF9C7A52); break;
      case CropFamily.mango:
        // Mango orchard — deep red-brown laterite soil
        c1 = const Color(0xFF4E2A10); c2 = const Color(0xFF7A4A25); break;
      case CropFamily.apple:
        // Apple orchard — rich dark mountain soil
        c1 = const Color(0xFF3B2A1A); c2 = const Color(0xFF6B4A2A); break;
      case CropFamily.banana:
        // Banana plantation — dark fertile tropical soil
        c1 = const Color(0xFF2A3A1A); c2 = const Color(0xFF4A6A2A); break;
      case CropFamily.coconut:
        // Coconut palm — sandy coastal/tropical soil
        c1 = const Color(0xFF5C4A2A); c2 = const Color(0xFF8C7A4A); break;
      case CropFamily.tomato:
        // Tomato field — rich dark loamy soil
        c1 = const Color(0xFF4A3020); c2 = const Color(0xFF7A5035); break;
      default:
        // Universal farmland soil — dark → light brown gradient
        c1 = const Color(0xFF6D4C41); c2 = const Color(0xFFA1887F);
    }
    canvas.drawPath(clip, Paint()..color = c1);
    canvas.drawPath(clip, Paint()
      ..shader = ui.Gradient.linear(
        Offset(b.left, b.top), Offset(b.left, b.bottom),
        [c1, c2.withOpacity(0.85)],
      ));

    // Subtle soil texture — faint horizontal furrow lines
    final furrowPaint = Paint()
      ..color = const Color(0xFF4E342E).withOpacity(0.18)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final furrowSpacing = (b.height / 14).clamp(4.0, 18.0);
    for (var y = b.top + furrowSpacing; y < b.bottom; y += furrowSpacing) {
      canvas.drawLine(Offset(b.left, y), Offset(b.right, y), furrowPaint);
    }
  }

  // ─── Bitmap plant rendering (corn / wheat PNG) ────────────────────────

  void _drawBitmapPlants(Canvas canvas, Rect screen) {
    final isCorn  = family == CropFamily.corn;
    const double cornBase  = 32.0;
    const double wheatBase = 22.0;
    final baseW   = isCorn ? cornBase : wheatBase;
    final aspect  = bitmapImg!.height / bitmapImg!.width;
    final maxSway = (isCorn ? 5.0 : 9.0) * pi / 180.0;
    final paint   = Paint()
      ..isAntiAlias   = true
      ..filterQuality = FilterQuality.high;

    // ── Screen-space grid: iterate rows top→bottom across full polygon ──
    // This guarantees 100% coverage with no gap at any edge.
    final b       = _polyBounds();
    final fw      = baseW;
    final fh      = fw * aspect;
    final colGap  = fw  * 0.88;   // horizontal spacing
    final rowGap  = fh  * 0.75;   // vertical spacing (overlap rows slightly)
    final totalH  = b.bottom - b.top;

    var rowY = b.top + fh;       // first base row: plant tops start at b.top
    var row  = 0;
    while (rowY <= b.bottom + fh) {
      final rowFrac = totalH > 0 ? ((rowY - b.top) / totalH).clamp(0.0, 1.0) : 0.0;
      final stagger = (row % 2 == 0) ? 0.0 : colGap * 0.5;
      var colX = b.left + stagger;
      var col  = 0;
      while (colX <= b.right + colGap) {
        final seed     = Object.hash(row * 1000 + col, 42);
        final rng      = Random(seed);
        final thisW    = fw  * (0.82 + rng.nextDouble() * 0.36);
        final thisH    = thisW * aspect;
        final phase    = rng.nextDouble() * pi * 2;
        final rot      = (rng.nextDouble() - 0.5) * 8 * pi / 180;
        final swayAngle = sin(wind * pi * 2 + phase) * maxSway * _leanSign *
                          (0.5 + _speedN * 0.5);
        final opacity  = (0.82 + rowFrac * 0.18).clamp(0.0, 1.0);
        final jx = (phase - pi) * 1.0;
        final jy = (rot * 15).clamp(-2.0, 2.0);

        paint.color = Color.fromRGBO(255, 255, 255, opacity);
        canvas.save();
        canvas.translate(colX + jx, rowY + jy);
        canvas.rotate(rot + swayAngle);
        canvas.translate(-thisW / 2, -thisH);
        canvas.drawImageRect(bitmapImg!, _srcRect,
            Rect.fromLTWH(0, 0, thisW, thisH), paint);
        canvas.restore();

        colX += colGap;
        col++;
      }
      rowY += rowGap;
      row++;
    }
  }

  // ─── Custom image tiling — stamps imagePath asset at every plant point ──
  //
  // Each stamp is rendered at a FIXED screen size of 25–40 px (not geo-scaled)
  // so crops are always clearly visible regardless of zoom level.
  // Natural variation is applied per-plant: ±20% size, random rotation,
  // slight position jitter. Hard-clipped to polygon boundary.

  void _drawImageTile(Canvas canvas, Rect screen, ui.Image img) {
    final srcRect = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());
    final aspect  = img.height / img.width;

    // ── Fixed visible size: 30 px wide base, aspect-correct height ──────
    // This guarantees crops are always recognisable (25–40 px range).
    const double baseSize = 30.0;
    final maxSway = 5.0 * pi / 180.0;

    final paint = Paint()
      ..isAntiAlias   = true
      ..filterQuality = FilterQuality.high;

    for (final pp in plants) {
      if (!screen.contains(pp.px)) continue;

      // ±20 % random size variation per plant
      final sizeVariation = 0.80 + pp.p.scale * 0.40; // scale is 0.8–1.2 → gives 0.80–1.28
      final fw = (baseSize * sizeVariation).clamp(22.0, 42.0);
      final fh = fw * aspect;

      // Wind sway
      final swayAngle = sin(wind * pi * 2 + pp.p.phase) * maxSway *
                        _leanSign * (0.5 + _speedN * 0.5);

      // Full opacity — crops must be clearly visible against brown soil
      paint.color = Color.fromRGBO(
          255, 255, 255,
          (pp.p.opacity * (0.88 + pp.p.rowFrac * 0.12)).clamp(0.0, 1.0));

      canvas.save();
      // Small random position jitter (±3 px) removes grid regularity
      final jx = (pp.p.phase - pi) * 1.2; // deterministic, looks random
      final jy = (pp.p.rot * 20).clamp(-3.0, 3.0);
      canvas.translate(pp.px.dx + jx, pp.px.dy + jy);
      canvas.rotate(pp.p.rot + swayAngle);   // gentle tilt + wind
      canvas.translate(-fw / 2, -fh);        // anchor at base-centre
      canvas.drawImageRect(img, srcRect, Rect.fromLTWH(0, 0, fw, fh), paint);
      canvas.restore();
    }
  }

  // ─── Vector plant rendering (all other families) ─────────────────────

  void _drawVectorPlants(Canvas canvas, Rect screen, Rect bounds) {
    // ── Screen-space grid: iterate rows top→bottom across full polygon ──
    // Covers 100% of the polygon with no gap at top or any other edge.
    final b        = _polyBounds();
    final plantH   = _typicalPlantHeightPx();
    final colGap   = plantH * 0.52;   // horizontal density
    final rowGap   = plantH * 0.68;   // vertical — slight overlap between rows
    final totalH   = b.bottom - b.top;

    var rowY = b.top + plantH;        // first row: tops start at polygon top
    var row  = 0;
    while (rowY <= b.bottom + plantH) {
      final rowFrac = totalH > 0 ? ((rowY - b.top) / totalH).clamp(0.0, 1.0) : 0.0;
      final stagger = (row % 2 == 0) ? 0.0 : colGap * 0.5;
      var colX = b.left + stagger;
      var col  = 0;
      while (colX <= b.right + colGap) {
        final seed  = Object.hash(row * 1000 + col, 77);
        final rng   = Random(seed);
        final fakePlant = _Plant(
          ll:      const LatLng(0, 0),
          rot:     (rng.nextDouble() - 0.5) * 8 * pi / 180,
          scale:   0.82 + rng.nextDouble() * 0.36,
          phase:   rng.nextDouble() * pi * 2,
          rowFrac: rowFrac,
          opacity: 0.80 + rng.nextDouble() * 0.20,
          variant: rng.nextInt(3),
        );
        _drawOnePlant(canvas, _PxPlant(Offset(colX, rowY), fakePlant));
        colX += colGap;
        col++;
      }
      rowY += rowGap;
      row++;
    }
  }

  double _typicalPlantHeightPx() {
    switch (family) {
      case CropFamily.corn:
      case CropFamily.sugarcane: return 48.0;
      case CropFamily.tree:      return 44.0;
      case CropFamily.mango:     return 50.0;
      case CropFamily.apple:     return 48.0;
      case CropFamily.banana:    return 52.0;
      case CropFamily.coconut:   return 58.0;
      case CropFamily.sunflower: return 40.0;
      case CropFamily.tomato:    return 26.0;
      case CropFamily.wheat:     return 20.0;
      case CropFamily.rice:      return 16.0;
      default:                   return 22.0;
    }
  }

  void _drawOnePlant(Canvas canvas, _PxPlant pp) {
    final x = pp.px.dx, y = pp.px.dy;
    final s = pp.p.scale;
    final sw = sin(wind * pi * 2 + pp.p.phase) * _leanSign;
    final rw = sin(rustle * pi + pp.p.phase * 0.7) * _leanSign;

    switch (family) {
      case CropFamily.wheat:    _wheat(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.rice:     _rice(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.corn:     _cornVector(canvas, x, y, s, sw, pp.p); break;
      case CropFamily.sugarcane:_sugarcane(canvas, x, y, s, sw, pp.p); break;
      case CropFamily.cotton:   _cotton(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.sunflower:_sunflower(canvas, x, y, s, sw, pp.p); break;
      case CropFamily.mustard:  _mustard(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.legume:   _legume(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.veggie:   _veggie(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.tomato:   _veggie(canvas, x, y, s, sw, rw, pp.p); break; // handled by _drawTomatoField
      case CropFamily.tuber:    _tuber(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.tree:     _tree(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.mango:    break; // handled by _drawMangoBitmapOrchard
      case CropFamily.apple:    break; // handled by _drawMangoBitmapOrchard
      case CropFamily.banana:   break; // handled by _drawMangoBitmapOrchard
      case CropFamily.coconut:  break; // handled by _drawMangoBitmapOrchard
      case CropFamily.herb:     _herb(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.grass:    _grass(canvas, x, y, s, sw, rw, pp.p); break;
      case CropFamily.grape:    break; // handled by _drawVineyard — never reaches here
      case CropFamily.brinjal:  break; // handled by _drawBrinjalBitmapField
      case CropFamily.pepper:   break; // handled by _drawPepperBitmapField
      case CropFamily.cabbage:  break; // handled by _drawCabbageField — never reaches here
      case CropFamily.marigold: break; // handled by _drawMarigoldField — never reaches here
      case CropFamily.sesame:   break; // handled by _drawSesameField — never reaches here
    }
  }

  // ── WHEAT — dense golden stalks with ear head ─────────────────────────

  void _wheat(Canvas canvas, double x, double y, double s,
              double sw, double rw, _Plant p) {
    final h = (16.0 + p.variant * 3.0) * s;
    final baseAmp = (0.8 + _speedN * 3.0) * s;
    final sway = sw * baseAmp + rw * 0.5 * s;

    // Stalk color varies from green to golden by rowFrac
    final stalkC = Color.lerp(
        const Color(0xFF5D8A2A), const Color(0xFFC8A23A), p.rowFrac)!;

    // Curved stalk using quadratic bezier
    final path = ui.Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + sway * 0.4, y - h * 0.6, x + sway, y - h);
    canvas.drawPath(path, Paint()
      ..color = stalkC.withOpacity(0.90)
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Ear: teardrop shape at top
    final earX = x + sway, earY = y - h;
    final earH = 5.0 * s;
    final earPath = ui.Path()
      ..moveTo(earX, earY)
      ..cubicTo(
          earX - 1.5 * s, earY - earH * 0.4,
          earX - 1.5 * s, earY - earH * 0.8,
          earX,          earY - earH)
      ..cubicTo(
          earX + 1.5 * s, earY - earH * 0.8,
          earX + 1.5 * s, earY - earH * 0.4,
          earX, earY);
    canvas.drawPath(earPath, Paint()
      ..color = Color.lerp(const Color(0xFF8FBB3A), const Color(0xFFE8C04A), p.rowFrac)!
          .withOpacity(0.95)
      ..style = PaintingStyle.fill);

    // Awns (bristles) at top of ear — makes wheat look realistic
    if (s > 0.6) {
      for (var i = -2; i <= 2; i++) {
        final awnBase = Offset(earX + i * 0.8 * s, earY - earH * 0.5);
        canvas.drawLine(awnBase,
          Offset(awnBase.dx + sway * 0.15 + i * 0.5 * s, awnBase.dy - 4 * s),
          Paint()
            ..color = const Color(0xFFD4AA3A).withOpacity(0.75)
            ..strokeWidth = 0.7 * s
            ..strokeCap = StrokeCap.round);
      }
    }

    // Side leaf
    if (p.variant != 1) {
      final lfX = x + sway * 0.5, lfY = y - h * 0.45;
      canvas.drawLine(
        Offset(lfX, lfY),
        Offset(lfX + (p.variant == 0 ? 4 : -4) * s + rw, lfY - 2 * s),
        Paint()
          ..color = stalkC.withOpacity(0.70)
          ..strokeWidth = 1.0 * s
          ..strokeCap = StrokeCap.round);
    }
  }

  // ── RICE — shorter, clustered, slightly drooping panicle ──────────────

  void _rice(Canvas canvas, double x, double y, double s,
             double sw, double rw, _Plant p) {
    final h = (13.0 + p.variant * 2.0) * s;
    final sway = sw * (0.6 + _speedN * 2.5) * s;

    final stalkC = Color.lerp(
        const Color(0xFF4A7A22), const Color(0xFFB8A040), p.rowFrac * 0.5)!;

    // Stalk
    final path = ui.Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + sway * 0.3, y - h * 0.7, x + sway, y - h);
    canvas.drawPath(path, Paint()
      ..color = stalkC.withOpacity(0.88)
      ..strokeWidth = 1.1 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Drooping panicle (rice head droops under grain weight)
    final panBase = Offset(x + sway, y - h);
    final panTip  = Offset(panBase.dx + sway * 0.4 + 2 * s, panBase.dy + 3 * s);
    canvas.drawLine(panBase, panTip, Paint()
      ..color = const Color(0xFFD4B84A).withOpacity(0.90)
      ..strokeWidth = 1.0 * s
      ..strokeCap = StrokeCap.round);

    // Small grain dots along panicle
    for (var i = 0; i < 4; i++) {
      final t = i / 3.0;
      canvas.drawCircle(
        Offset(panBase.dx + (panTip.dx - panBase.dx) * t,
               panBase.dy + (panTip.dy - panBase.dy) * t),
        0.9 * s,
        Paint()..color = const Color(0xFFC8B060).withOpacity(0.85));
    }
  }

  // ── CORN (vector fallback when PNG not loaded) ────────────────────────

  void _cornVector(Canvas canvas, double x, double y, double s,
                   double sw, _Plant p) {
    final h = (36.0 + p.variant * 6.0) * s;
    final sway = sw * (0.5 + _speedN * 2.0) * s;

    // Thick stalk
    final stalkPath = ui.Path()
      ..moveTo(x, y)
      ..cubicTo(x + sway * 0.3, y - h * 0.4,
                x + sway * 0.6, y - h * 0.7,
                x + sway, y - h);
    canvas.drawPath(stalkPath, Paint()
      ..color = const Color(0xFF2E6A14).withOpacity(0.92)
      ..strokeWidth = 3.0 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Two large drooping leaves
    for (final side in [-1.0, 1.0]) {
      final lx = x + sway * 0.5, ly = y - h * 0.5;
      canvas.drawLine(
        Offset(lx, ly),
        Offset(lx + side * 10 * s + sway * 0.4, ly + 4 * s),
        Paint()
          ..color = const Color(0xFF3A8820).withOpacity(0.80)
          ..strokeWidth = 2.5 * s
          ..strokeCap = StrokeCap.round);
    }

    // Ear (yellow cob) midway
    if (s > 0.7) {
      final cx = x + sway * 0.7, cy = y - h * 0.6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + 4 * s, cy), width: 7 * s, height: 12 * s),
          Radius.circular(3 * s),
        ),
        Paint()..color = const Color(0xFFE8C030).withOpacity(0.90));
      // Husk
      canvas.drawLine(
        Offset(cx, cy - 5 * s),
        Offset(cx + 3 * s, cy - 8 * s),
        Paint()..color = const Color(0xFF4A7A1A).withOpacity(0.75)..strokeWidth = 2 * s);
    }

    // Tassel at top
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(x + sway, y - h),
        Offset(x + sway + i * 2.5 * s, y - h - 6 * s),
        Paint()
          ..color = const Color(0xFFC8A840).withOpacity(0.70)
          ..strokeWidth = 0.8 * s
          ..strokeCap = StrokeCap.round);
    }
  }

  // ── SUGARCANE — very tall, thick, jointed canes ───────────────────────

  void _sugarcane(Canvas canvas, double x, double y, double s,
                  double sw, _Plant p) {
    final h = (48.0 + p.variant * 8.0) * s;
    final sway = sw * (0.3 + _speedN * 1.5) * s;

    // Draw 2–3 canes per instance for density
    for (var c = 0; c < 2 + p.variant; c++) {
      final offX = (c - 1) * 3.0 * s;
      final path = ui.Path()
        ..moveTo(x + offX, y)
        ..cubicTo(x + offX + sway * 0.2, y - h * 0.35,
                  x + offX + sway * 0.5, y - h * 0.65,
                  x + offX + sway, y - h);
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF3A7A20).withOpacity(0.85)
        ..strokeWidth = (2.5 - c * 0.3) * s
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);

      // Joints (nodes) along the cane
      for (var j = 1; j <= 3; j++) {
        final t = j / 4.0;
        final jx = x + offX + sway * t;
        final jy = y - h * t;
        canvas.drawCircle(Offset(jx, jy), 1.5 * s,
          Paint()..color = const Color(0xFF5A9A30).withOpacity(0.75));
        // Short leaf at each joint
        canvas.drawLine(Offset(jx, jy),
          Offset(jx + (c.isEven ? 6 : -6) * s, jy - 3 * s),
          Paint()
            ..color = const Color(0xFF4A8820).withOpacity(0.65)
            ..strokeWidth = 1.2 * s
            ..strokeCap = StrokeCap.round);
      }
    }
  }

  // ── COTTON — bushy with white fluffy bolls ────────────────────────────

  void _cotton(Canvas canvas, double x, double y, double s,
               double sw, double rw, _Plant p) {
    final h = (22.0 + p.variant * 4.0) * s;
    final sway = sw * (0.8 + _speedN * 1.5) * s;

    // Main stem
    canvas.drawLine(Offset(x, y), Offset(x + sway * 0.4, y - h),
      Paint()
        ..color = const Color(0xFF4A6A20).withOpacity(0.80)
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round);

    // Bushy branches with leaves
    for (var b = 0; b < 3; b++) {
      final t = 0.3 + b * 0.25;
      final bx = x + sway * t * 0.4, by = y - h * t;
      final side = (b % 2 == 0 ? 1 : -1).toDouble();
      canvas.drawLine(Offset(bx, by),
        Offset(bx + side * 8 * s + rw, by - 4 * s),
        Paint()
          ..color = const Color(0xFF5A8A2A).withOpacity(0.72)
          ..strokeWidth = 1.4 * s..strokeCap = StrokeCap.round);

      // Cotton boll (round fluffy white)
      if (b != 1 || p.variant > 0) {
        final boll = Offset(bx + side * 9 * s + rw, by - 5 * s);
        canvas.drawCircle(boll, 3.5 * s, Paint()
          ..color = Colors.white.withOpacity(0.88)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * s));
        canvas.drawCircle(boll, 2.5 * s, Paint()
          ..color = Colors.white.withOpacity(0.95));
      }
    }
  }

  // ── SUNFLOWER — tall with large yellow head ───────────────────────────

  void _sunflower(Canvas canvas, double x, double y, double s,
                  double sw, _Plant p) {
    final h = (38.0 + p.variant * 5.0) * s;
    final sway = sw * (0.4 + _speedN * 1.5) * s;

    // Stem
    final stemPath = ui.Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + sway * 0.4, y - h * 0.6, x + sway, y - h);
    canvas.drawPath(stemPath, Paint()
      ..color = const Color(0xFF3A6A18).withOpacity(0.88)
      ..strokeWidth = 2.8 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Large stem leaves
    for (final dir in [-1.0, 1.0]) {
      final lx = x + sway * 0.5, ly = y - h * 0.45;
      final leafPath = ui.Path()
        ..moveTo(lx, ly)
        ..quadraticBezierTo(lx + dir * 10 * s, ly - 3 * s, lx + dir * 14 * s, ly + 2 * s)
        ..quadraticBezierTo(lx + dir * 8 * s, ly + 4 * s, lx, ly);
      canvas.drawPath(leafPath, Paint()
        ..color = const Color(0xFF4A8822).withOpacity(0.75)
        ..style = PaintingStyle.fill);
    }

    // Head: dark center disc
    final hx = x + sway, hy = y - h;
    final headR = 7.0 * s;
    canvas.drawCircle(Offset(hx, hy), headR, Paint()
      ..color = const Color(0xFF3A2A10).withOpacity(0.90));
    // Ring of petals
    for (var i = 0; i < 16; i++) {
      final angle = (i / 16) * pi * 2;
      final px = hx + cos(angle) * (headR + 2 * s);
      final py = hy + sin(angle) * (headR + 2 * s);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(px, py),
          width: 4.5 * s, height: 2.5 * s,
        ),
        Paint()..color = const Color(0xFFFFCC00).withOpacity(0.92),
      );
    }
    // Center detail
    canvas.drawCircle(Offset(hx, hy), headR * 0.65, Paint()
      ..color = const Color(0xFF5A3A18).withOpacity(0.85));
  }

  // ── MUSTARD — medium height, clusters of yellow flowers ───────────────

  void _mustard(Canvas canvas, double x, double y, double s,
                double sw, double rw, _Plant p) {
    final h = (18.0 + p.variant * 3.0) * s;
    final sway = sw * (1.0 + _speedN * 3.0) * s + rw * 0.6 * s;

    // Main stem
    final path = ui.Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + sway * 0.4, y - h * 0.6, x + sway, y - h);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF4A7A22).withOpacity(0.85)
      ..strokeWidth = 1.4 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Cluster of tiny yellow flowers at top
    final topX = x + sway, topY = y - h;
    for (var i = 0; i < 5; i++) {
      final angle = (i / 5) * pi * 2;
      final fx = topX + cos(angle) * 2.5 * s;
      final fy = topY + sin(angle) * 2.5 * s;
      canvas.drawCircle(Offset(fx, fy), 2.0 * s, Paint()
        ..color = const Color(0xFFFFDD00).withOpacity(0.92));
    }
    canvas.drawCircle(Offset(topX, topY), 1.5 * s, Paint()
      ..color = const Color(0xFFFFEE40).withOpacity(0.95));

    // Side branches
    if (p.variant != 0) {
      canvas.drawLine(
        Offset(x + sway * 0.6, y - h * 0.65),
        Offset(x + sway * 0.6 + 5 * s, y - h * 0.65 - 3 * s),
        Paint()
          ..color = const Color(0xFF4A7A22).withOpacity(0.70)
          ..strokeWidth = 0.9 * s..strokeCap = StrokeCap.round);
    }
  }

  // ── LEGUME — bushy, compound leaves, pods visible ─────────────────────

  void _legume(Canvas canvas, double x, double y, double s,
               double sw, double rw, _Plant p) {
    final h = (16.0 + p.variant * 3.0) * s;
    final sway = sw * (0.5 + _speedN * 1.5) * s;

    // Main stem (short, bushy habit)
    canvas.drawLine(Offset(x, y), Offset(x + sway * 0.3, y - h * 0.7),
      Paint()
        ..color = const Color(0xFF3A6A20).withOpacity(0.80)
        ..strokeWidth = 1.8 * s..strokeCap = StrokeCap.round);

    // Compound leaf clusters (3 leaflets each)
    for (var b = 0; b < 2; b++) {
      final bx = x + sway * 0.2, by = y - h * (0.4 + b * 0.3);
      for (var l = 0; l < 3; l++) {
        final angle = (l / 3.0) * pi - pi / 2 + rw * 0.3;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(bx + cos(angle) * 5 * s, by + sin(angle) * 3 * s),
            width: 6 * s, height: 4 * s,
          ),
          Paint()..color = const Color(0xFF5A9030).withOpacity(0.78));
      }
    }

    // Pods (elongated green)
    if (p.variant > 0) {
      final podX = x + sway * 0.4, podY = y - h * 0.55;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(podX, podY), width: 2.5 * s, height: 8 * s),
          Radius.circular(1.5 * s)),
        Paint()..color = const Color(0xFF4A7A20).withOpacity(0.85));
    }
  }

  // ── VEGGIE — tomato/capsicum/brinjal row crops ────────────────────────

  void _veggie(Canvas canvas, double x, double y, double s,
               double sw, double rw, _Plant p) {
    final h = (18.0 + p.variant * 3.0) * s;
    final sway = sw * (0.5 + _speedN * 1.5) * s;
    final isTomato  = cropName(family) == 'tomato';
    final isCapsicum = p.variant == 2;

    // Stem
    canvas.drawLine(Offset(x, y), Offset(x + sway * 0.3, y - h),
      Paint()
        ..color = const Color(0xFF3A6020).withOpacity(0.82)
        ..strokeWidth = 2.0 * s..strokeCap = StrokeCap.round);

    // Leaf cluster
    for (var l = 0; l < 4; l++) {
      final angle = (l / 4.0) * pi * 2 + rw * 0.2;
      final lx = x + sway * 0.3 + cos(angle) * 7 * s;
      final ly = y - h * 0.5 + sin(angle) * 4 * s;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(lx, ly), width: 8 * s, height: 5 * s),
        Paint()..color = const Color(0xFF4A8020).withOpacity(0.72));
    }

    // Fruit
    final fruitC = isTomato
        ? const Color(0xFFE03020)
        : isCapsicum
            ? const Color(0xFFE05010)
            : const Color(0xFF5020A0);
    canvas.drawCircle(
      Offset(x + sway * 0.3 + 4 * s, y - h * 0.4),
      isTomato ? 4.0 * s : 3.0 * s,
      Paint()..color = fruitC.withOpacity(0.88));
  }

  // ── TUBER — potato/onion/carrot — low leafy rosettes ─────────────────

  void _tuber(Canvas canvas, double x, double y, double s,
              double sw, double rw, _Plant p) {
    final sway = sw * (0.4 + _speedN * 1.2) * s + rw * 0.5 * s;

    // Foliage rosette (leaves spread from ground level)
    final leafCount = 4 + p.variant;
    for (var l = 0; l < leafCount; l++) {
      final angle = (l / leafCount.toDouble()) * pi * 2 + sway * 0.15;
      final lLen = (10.0 + p.variant * 2) * s;
      final leafPath = ui.Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + cos(angle) * lLen * 0.5 + sway * 0.3,
          y + sin(angle) * lLen * 0.5 - lLen * 0.2,
          x + cos(angle) * lLen + sway,
          y + sin(angle) * lLen * 0.3 - lLen * 0.1,
        );
      canvas.drawPath(leafPath, Paint()
        ..color = const Color(0xFF4A8020).withOpacity(0.78)
        ..strokeWidth = 1.8 * s
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    }

    // Hint of underground bulb at base
    canvas.drawCircle(Offset(x, y + 2 * s), 3.0 * s, Paint()
      ..color = const Color(0xFFB88040).withOpacity(0.40));
  }

  // ── TREE — mango/coconut/banana canopy ───────────────────────────────

  void _tree(Canvas canvas, double x, double y, double s,
             double sw, double rw, _Plant p) {
    final h = (55.0 + p.variant * 10.0) * s;
    final sway = sw * (0.3 + _speedN * 1.2) * s;
    final isCoconut = p.variant == 0;
    final isBanana  = p.variant == 1;

    // Trunk
    final trunkPath = ui.Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + sway * 1.5, y - h * 0.45, x + sway, y - h);
    canvas.drawPath(trunkPath, Paint()
      ..color = (isCoconut
          ? const Color(0xFF7A5A30)
          : isBanana
              ? const Color(0xFF6A8820)
              : const Color(0xFF6A4A28)).withOpacity(0.88)
      ..strokeWidth = (isCoconut ? 4.5 : isBanana ? 5.5 : 5.0) * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    final topX = x + sway, topY = y - h;

    if (isCoconut) {
      // Coconut palm fronds
      for (var f = 0; f < 7; f++) {
        final ang = (f / 7.0) * pi * 2 - pi / 2 + rw * 0.15;
        final frondPath = ui.Path()
          ..moveTo(topX, topY)
          ..quadraticBezierTo(
            topX + cos(ang) * 14 * s, topY + sin(ang) * 10 * s,
            topX + cos(ang) * 22 * s, topY + sin(ang) * 18 * s,
          );
        canvas.drawPath(frondPath, Paint()
          ..color = const Color(0xFF3A7020).withOpacity(0.80)
          ..strokeWidth = 2.2 * s..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
      }
      // Coconuts
      if (s > 0.7) {
        for (var c = 0; c < 3; c++) {
          final ang = (c / 3.0) * pi * 2;
          canvas.drawCircle(
            Offset(topX + cos(ang) * 5 * s, topY + sin(ang) * 4 * s),
            3.0 * s, Paint()..color = const Color(0xFF8A6A30).withOpacity(0.82));
        }
      }
    } else if (isBanana) {
      // Banana large paddle leaves
      for (var l = 0; l < 5; l++) {
        final ang = (l / 5.0) * pi * 2 + rw * 0.1;
        final leafPath = ui.Path()
          ..moveTo(topX, topY)
          ..quadraticBezierTo(
            topX + cos(ang) * 12 * s, topY + sin(ang) * 8 * s - 2 * s,
            topX + cos(ang) * 20 * s, topY + sin(ang) * 14 * s,
          );
        canvas.drawPath(leafPath, Paint()
          ..color = const Color(0xFF4A8C20).withOpacity(0.80)
          ..strokeWidth = 4.0 * s..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
      }
    } else {
      // Mango / fruit tree — round canopy
      final canopyR = 18.0 * s;
      // Outer canopy shadow
      canvas.drawCircle(Offset(topX, topY), canopyR + 2 * s, Paint()
        ..color = const Color(0xFF1A4010).withOpacity(0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * s));
      // Main canopy
      canvas.drawCircle(Offset(topX, topY), canopyR, Paint()
        ..color = const Color(0xFF2E6A18).withOpacity(0.88));
      // Highlight patch
      canvas.drawCircle(Offset(topX - 4 * s, topY - 4 * s), canopyR * 0.5, Paint()
        ..color = const Color(0xFF4A8A28).withOpacity(0.65));
      // Fruit
      if (s > 0.7) {
        for (var f = 0; f < 4; f++) {
          final ang = (f / 4.0) * pi * 2 + p.phase;
          canvas.drawCircle(
            Offset(topX + cos(ang) * 10 * s, topY + sin(ang) * 8 * s),
            3.5 * s,
            Paint()..color = const Color(0xFFF0800A).withOpacity(0.85));
        }
      }
    }
  }

  // ── HERB — dense low aromatic plants ─────────────────────────────────

  void _herb(Canvas canvas, double x, double y, double s,
             double sw, double rw, _Plant p) {
    final sway = sw * (0.6 + _speedN * 2.0) * s + rw * 0.7 * s;
    final h = (10.0 + p.variant * 2.0) * s;

    // Multiple thin stems
    for (var i = 0; i < 3; i++) {
      final offX = (i - 1) * 2.5 * s;
      canvas.drawLine(Offset(x + offX, y),
        Offset(x + offX + sway, y - h),
        Paint()
          ..color = const Color(0xFF4A8A30).withOpacity(0.82)
          ..strokeWidth = 1.0 * s..strokeCap = StrokeCap.round);

      // Tiny oval leaves on each stem
      for (var l = 0; l < 3; l++) {
        final ly = y - h * (0.3 + l * 0.3);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x + offX + sway * (l / 2.0) * 0.3 + (i.isEven ? 2 : -2) * s, ly),
            width: 4 * s, height: 2.5 * s),
          Paint()..color = const Color(0xFF5AAA40).withOpacity(0.78));
      }
    }
  }

  // ── GRASS — generic pasture / unidentified crop ───────────────────────

  void _grass(Canvas canvas, double x, double y, double s,
              double sw, double rw, _Plant p) {
    final sway = sw * (1.2 + _speedN * 3.5) * s + rw * 0.8 * s;
    final blades = 2 + p.variant;

    for (var b = 0; b < blades; b++) {
      final offX = (b - blades / 2.0) * 2.5 * s;
      final h = (9.0 + b * 1.5 + p.variant) * s;
      final bladePath = ui.Path()
        ..moveTo(x + offX, y)
        ..quadraticBezierTo(
          x + offX + sway * 0.3, y - h * 0.55,
          x + offX + sway, y - h);
      canvas.drawPath(bladePath, Paint()
        ..color = const Color(0xFF48A030).withOpacity(0.78 - p.rowFrac * 0.15)
        ..strokeWidth = (1.1 + b * 0.1) * s
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    }
  }

  static String cropName(CropFamily f) => f.name;

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.wind != wind || old.rustle != rustle ||
      old.mpp != mpp || old.plants.length != plants.length ||
      old.polygonPx.length != polygonPx.length ||
      (old.polygonPx.isNotEmpty && polygonPx.isNotEmpty &&
       old.polygonPx.first != polygonPx.first) ||
      (old.plants.isNotEmpty && plants.isNotEmpty &&
       old.plants.first.px != plants.first.px);
}

// ─── Plant grid builder ────────────────────────────────────────────────────

List<_Plant> _buildGrid(List<LatLng> poly, double rowM, double colM) {
  if (poly.length < 3) return [];

  var minLat = 90.0, maxLat = -90.0;
  var minLng = 180.0, maxLng = -180.0;
  for (final p in poly) {
    if (p.latitude  < minLat) minLat = p.latitude;
    if (p.latitude  > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  final cLat = (minLat + maxLat) / 2;

  var latStep = rowM / 111320.0;
  var lngStep = colM / (111320.0 * cos(cLat * pi / 180));
  const maxP  = 6000;

  for (var iter = 0; iter < 20; iter++) {
    final est = ((maxLat - minLat) / latStep).ceil() *
                ((maxLng - minLng) / lngStep).ceil();
    if (est <= maxP * 1.4) break;
    latStep *= 1.18;
    lngStep *= 1.18;
  }

  final out = <_Plant>[];
  var row = 0;

  // Start one step before bbox and end one step after — ensures the
  // plant grid reaches the polygon boundary on all sides.
  for (var lat = minLat - latStep; lat <= maxLat + latStep; lat += latStep) {
    final stagger  = (row % 2 == 0) ? 0.0 : lngStep * 0.5;
    // Row-level jitter seeded by row index only — same for every field
    final rowRng   = Random(row * 131071);
    final rowJit   = (rowRng.nextDouble() - 0.5) * lngStep * 0.08;
    final rowFrac  = (lat - minLat) / ((maxLat - minLat).clamp(1e-9, 1.0));

    var col = 0;
    for (var lng = minLng - lngStep + stagger + rowJit;
         lng <= maxLng + lngStep; lng += lngStep) {
      // ── KEY CHANGE ──────────────────────────────────────────────────
      // Seed from (row, col) indices — NOT from absolute lat/lng.
      // This makes the per-plant variation (rotation, scale, phase,
      // variant) identical for any two fields of the same crop type,
      // regardless of where on the map they are located.
      final seed = Object.hash(row, col);
      final rng  = Random(seed);

      final jLat = (rng.nextDouble() - 0.5) * latStep * 0.15;
      final jLng = (rng.nextDouble() - 0.5) * lngStep * 0.15;
      final ll   = LatLng(lat + jLat, lng + jLng);
      // Use the un-jittered grid point for the boundary check so edge
      // plants are never skipped due to jitter pushing them outside.
      final llCheck = LatLng(lat, lng + stagger + rowJit);
      if (!_inPoly(llCheck, poly) && !_inPoly(ll, poly)) continue;

      out.add(_Plant(
        ll:       ll,
        rot:      (rng.nextDouble() - 0.5) * 8 * pi / 180,
        scale:    0.80 + rng.nextDouble() * 0.40,
        phase:    rng.nextDouble() * pi * 2,
        rowFrac:  rowFrac,
        opacity:  0.80 + rng.nextDouble() * 0.20,
        variant:  rng.nextInt(3),
      ));
      if (out.length >= maxP) break;
      col++;
    }
    if (out.length >= maxP) break;
    row++;
  }

  // Back-to-front sort (painter's algorithm)
  out.sort((a, b) => b.ll.latitude.compareTo(a.ll.latitude));
  return out;
}

// ─── Utilities ────────────────────────────────────────────────────────────

List<Offset> _projectPoly(List<LatLng> poly, MapCamera cam) =>
    poly.map((ll) {
      final sp = cam.latLngToScreenPoint(ll);
      return Offset(sp.x.toDouble(), sp.y.toDouble());
    }).toList(growable: false);

double _mpp(double lat, double zoom) =>
    40075016.686 * cos(lat * pi / 180) / (256 * pow(2, zoom));

bool _polyEq(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude)
      return false;
  }
  return true;
}

bool _inPoly(LatLng p, List<LatLng> poly, {double eps = 5e-6}) {
  // Slightly inflate the test point tolerance so plants whose grid
  // position is exactly on or very near the polygon edge are included.
  final testLat = p.latitude;
  final testLng = p.longitude;
  var j = poly.length - 1;
  var inside = false;
  for (var i = 0; i < poly.length; j = i++) {
    final xi = poly[i].longitude, yi = poly[i].latitude;
    final xj = poly[j].longitude, yj = poly[j].latitude;
    // Check if point is on the edge segment (within eps) → include it
    final minY = yi < yj ? yi : yj;
    final maxY = yi > yj ? yi : yj;
    final minX = xi < xj ? xi : xj;
    final maxX = xi > xj ? xi : xj;
    if (testLat >= minY - eps && testLat <= maxY + eps &&
        testLng >= minX - eps && testLng <= maxX + eps) {
      final dy = yj - yi;
      if (dy.abs() > 1e-12) {
        final edgeX = (xj - xi) * (testLat - yi) / dy + xi;
        if ((testLng - edgeX).abs() < eps) return true;
      }
    }
    final dy = yj - yi;
    if (dy.abs() < 1e-12) continue;
    if (((yi > testLat) != (yj > testLat)) &&
        (testLng < (xj - xi) * (testLat - yi) / dy + xi)) {
      inside = !inside;
    }
  }
  return inside;
}
