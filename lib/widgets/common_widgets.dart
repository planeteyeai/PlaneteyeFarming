import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

// ── Labeled text field ──────────────────────────────────────────────────────
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.validator,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1.5)),
      ),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        validator: validator,
        decoration: InputDecoration(hintText: hint, suffixIcon: suffix,
          hintStyle: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
      ),
    ]);
  }
}

// ── Autocomplete search field ───────────────────────────────────────────────
class AutocompleteSearchField extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> suggestions;
  final void Function(String) onSelected;
  final String initial;

  const AutocompleteSearchField({
    super.key,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.onSelected,
    this.initial = '',
  });

  @override
  State<AutocompleteSearchField> createState() => _AutocompleteSearchFieldState();
}

class _AutocompleteSearchFieldState extends State<AutocompleteSearchField> {
  late TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  List<String> _filtered = [];
  OverlayEntry? _overlay;
  final LayerLink _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), _removeOverlay);
      }
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _filter(String q) {
    _filtered = q.isEmpty
        ? []
        : widget.suggestions.where((s) => s.toLowerCase().startsWith(q.toLowerCase())).toList()..sort();
    _removeOverlay();
    if (_filtered.isNotEmpty && _focus.hasFocus) _showOverlay();
  }

  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 300;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 62),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight, width: 2),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                itemBuilder: (_, i) => InkWell(
                  onTap: () {
                    _ctrl.text = _filtered[i];
                    widget.onSelected(_filtered[i]);
                    _removeOverlay();
                    _focus.unfocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(_filtered[i],
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 14)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(widget.label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1.5)),
      ),
      CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: (v) { widget.onSelected(v); _filter(v); },
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600),
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.borderLight, width: 2)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.borderLight, width: 2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
        ),
      ),
    ]);
  }
}

// ── Irrigation selector ─────────────────────────────────────────────────────
class IrrigationSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final void Function(String) onSelect;

  const IrrigationSelector({super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 8, bottom: 8),
        child: Text('IRRIGATION TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1.5)),
      ),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.5,
        children: options.map((type) {
          final sel = selected == type;
          return GestureDetector(
            onTap: () => onSelect(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: sel ? AppColors.greenLight : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sel ? AppColors.primary : AppColors.borderLight, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(type, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5,
                      color: sel ? AppColors.primary : AppColors.textLight)),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ── Green button ─────────────────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({super.key, required this.label, this.onTap, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          padding: const EdgeInsets.symmetric(vertical: 20),
          elevation: 8,
        ),
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                if (icon != null) ...[const SizedBox(width: 12), Icon(icon, size: 22)],
              ]),
      ),
    );
  }
}

// ── Back button ───────────────────────────────────────────────────────────────
class BackCircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color? color;
  const BackCircleButton({super.key, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
        ),
        child: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textLight),
      ),
    );
  }
}

// ── Section divider ────────────────────────────────────────────────────────────
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: AppColors.borderLight);
}

// ── Floating action button (dashboard) ─────────────────────────────────────
class FloatingActionBtn extends StatefulWidget {
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  final String label;

  const FloatingActionBtn({super.key, required this.icon, required this.bg, required this.onTap, required this.label});

  @override
  State<FloatingActionBtn> createState() => _FloatingActionBtnState();
}

class _FloatingActionBtnState extends State<FloatingActionBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 120), lowerBound: 0.0, upperBound: 1.0);
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
        CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Column(children: [
          // 3-D layered shadow effect
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Bottom "depth" layer (dark shadow disc)
              boxShadow: [
                // Deep bottom shadow for 3D lift
                BoxShadow(
                  color: widget.bg.withOpacity(0.55),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                  spreadRadius: 0,
                ),
                // Hard dark edge for 3D depth
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 5),
                  spreadRadius: -2,
                ),
                // Top highlight for 3D gloss
                BoxShadow(
                  color: Colors.white.withOpacity(0.25),
                  blurRadius: 2,
                  offset: const Offset(0, -2),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Gradient for the 3D glossy look
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _lighten(widget.bg, 0.18),
                    widget.bg,
                    _darken(widget.bg, 0.18),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.50),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                  blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Text(widget.label,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: 1)),
          ),
        ]),
      ),
    );
  }

  Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}
