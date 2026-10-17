// Dalabapay design system: reusable building blocks for every screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dp_icons.dart';
import 'dp_theme.dart';

// ---------------------------------------------------------------------------
// Icon
// ---------------------------------------------------------------------------

class DPIcon extends StatelessWidget {
  final DPIconData icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  const DPIcon(
    this.icon, {
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 1.75,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DP.ink;
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
        'fill="none" stroke="#000000" stroke-width="$strokeWidth" stroke-linecap="round" '
        'stroke-linejoin="round">${icon.body}</svg>';
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(
        svg,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// The Dalabapay mark, read from assets/images/dabalogo.png.
class DPLogoMark extends StatelessWidget {
  final double size;
  final bool tile;

  const DPLogoMark({super.key, this.size = 40, this.tile = false});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      'assets/images/dabalogo.png',
      width: tile ? size * 0.66 : size,
      height: tile ? size * 0.66 : size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _FallbackMark(size: tile ? size * 0.66 : size),
    );
    if (!tile) return img;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: DP.border),
      ),
      child: img,
    );
  }
}

class _FallbackMark extends StatelessWidget {
  final double size;
  const _FallbackMark({required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter()),
      );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.32, h * 0.24)
          ..lineTo(w * 0.5, h * 0.1)
          ..lineTo(w * 0.68, h * 0.24),
        p(const Color(0xFF7CC97A)));
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.18, h * 0.38)
          ..lineTo(w * 0.5, h * 0.62)
          ..lineTo(w * 0.82, h * 0.38),
        p(DP.green));
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.18, h * 0.64)
          ..lineTo(w * 0.5, h * 0.88)
          ..lineTo(w * 0.82, h * 0.64),
        p(DP.navy));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mark + "Dalabapay" wordmark.
class DPLogo extends StatelessWidget {
  final double height;
  const DPLogo({super.key, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: DP.font,
      fontSize: height * 0.9,
      fontWeight: FontWeight.w700,
      letterSpacing: -height * 0.03,
      height: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DPLogoMark(size: height),
        SizedBox(width: height * 0.12),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Dala', style: style.copyWith(color: DP.navy)),
            TextSpan(text: 'bapay', style: style.copyWith(color: DP.green)),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page scaffolding
// ---------------------------------------------------------------------------

class DPBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final DPIconData icon;
  const DPBackButton({super.key, this.onPressed, this.icon = DPIcons.arrowLeft});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DP.surface,
      borderRadius: BorderRadius.circular(DP.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rMd),
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DP.rMd),
            border: Border.all(color: DP.border),
          ),
          child: DPIcon(icon, size: 20, color: DP.ink),
        ),
      ),
    );
  }
}

/// Header row used at the top of every inner screen.
class DPHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const DPHeader({
    super.key,
    required this.title,
    this.showBack = true,
    this.onBack,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 8),
      child: Row(
        children: [
          if (showBack) ...[
            DPBackButton(onPressed: onBack),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(
              title,
              style: DPText.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null)
            DPLinkButton(label: actionLabel!, onPressed: onAction),
        ],
      ),
    );
  }
}

class DPLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  const DPLinkButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = DP.green,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(label, style: DPText.link.copyWith(color: color)),
      ),
    );
  }
}

/// Standard inner screen: header + scrollable body + optional pinned bottom.
class DPPage extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final List<Widget> children;
  final Widget? bottom;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final GlobalKey<FormState>? formKey;

  const DPPage({
    super.key,
    required this.title,
    required this.children,
    this.showBack = true,
    this.onBack,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.bottom,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 28),
    this.onRefresh,
    this.controller,
    this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: padding,
      children: children,
    );
    if (onRefresh != null) {
      list = RefreshIndicator(color: DP.green, onRefresh: onRefresh!, child: list);
    }
    if (formKey != null) {
      list = Form(key: formKey, child: list);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
          bottom: bottomNavigationBar == null,
          child: Column(
            children: [
              DPHeader(
                title: title,
                showBack: showBack,
                onBack: onBack,
                actionLabel: actionLabel,
                onAction: onAction,
                trailing: trailing,
              ),
              Expanded(child: list),
              if (bottom != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(DP.gutter, 10, DP.gutter, 14),
                  decoration: const BoxDecoration(color: DP.bg),
                  child: bottom,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large friendly headline with an optional supporting line.
class DPHeadline extends StatelessWidget {
  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  const DPHeadline(
    this.title, {
    super.key,
    this.subtitle,
    this.padding = const EdgeInsets.only(top: 12, bottom: 22),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DPText.display),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: DPText.bodyMuted),
          ],
        ],
      ),
    );
  }
}

class DPSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  const DPSectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(top: 24, bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: DPText.section)),
          if (actionLabel != null)
            DPLinkButton(label: actionLabel!, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Small label shown above a form field.
class DPFieldLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const DPFieldLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: DPText.label)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum DPButtonKind { primary, secondary, soft, navy, danger, ghost }

class DPButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final DPIconData? icon;
  final DPIconData? leadingIcon;
  final bool loading;
  final DPButtonKind kind;
  final bool expand;
  final double height;

  const DPButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingIcon,
    this.loading = false,
    this.kind = DPButtonKind.primary,
    this.expand = true,
    this.height = 54,
  });

  const DPButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingIcon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  }) : kind = DPButtonKind.secondary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    late Color bg, fg;
    BorderSide side = BorderSide.none;
    switch (kind) {
      case DPButtonKind.primary:
        bg = DP.green;
        fg = Colors.white;
        break;
      case DPButtonKind.secondary:
        bg = DP.surface;
        fg = DP.ink;
        side = const BorderSide(color: DP.border);
        break;
      case DPButtonKind.soft:
        bg = DP.greenSoft;
        fg = DP.navy;
        break;
      case DPButtonKind.navy:
        bg = DP.navy2;
        fg = Colors.white;
        break;
      case DPButtonKind.danger:
        bg = DP.dangerSoft;
        fg = DP.danger;
        break;
      case DPButtonKind.ghost:
        bg = Colors.transparent;
        fg = DP.green;
        break;
    }
    if (!enabled && !loading) {
      if (kind == DPButtonKind.primary || kind == DPButtonKind.navy) {
        bg = const Color(0xFFE6EAE4);
        fg = DP.muted;
      } else {
        fg = fg.withValues(alpha: 0.45);
      }
    }

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                DPIcon(leadingIcon!, size: 19, color: fg, strokeWidth: 2),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  style: DPText.button.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 10),
                DPIcon(icon!, size: 19, color: fg, strokeWidth: 2),
              ],
            ],
          );

    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rMd + 2),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

class DPField extends StatelessWidget {
  final String? label;
  final Widget? labelTrailing;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final Color? helperColor;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final DPIconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final Widget? prefix;
  final String? prefixText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? errorText;
  final TextStyle? style;
  final AutovalidateMode? autovalidateMode;
  final TextCapitalization textCapitalization;
  final EdgeInsetsGeometry margin;

  const DPField({
    super.key,
    this.label,
    this.labelTrailing,
    this.controller,
    this.hint,
    this.helper,
    this.helperColor,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.suffixIcon,
    this.onSuffixTap,
    this.prefix,
    this.prefixText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.textInputAction,
    this.autofillHints,
    this.errorText,
    this.style,
    this.autovalidateMode,
    this.textCapitalization = TextCapitalization.none,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    Widget? suffixWidget = suffix;
    if (suffixWidget == null && suffixIcon != null) {
      final ic = DPIcon(suffixIcon!, size: 20, color: DP.muted);
      suffixWidget = onSuffixTap == null
          ? Padding(padding: const EdgeInsets.all(14), child: ic)
          : IconButton(onPressed: onSuffixTap, icon: ic, splashRadius: 20);
    }
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) DPFieldLabel(label!, trailing: labelTrailing),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            obscureText: obscure,
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onSubmitted,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            maxLines: obscure ? 1 : maxLines,
            enabled: enabled,
            readOnly: readOnly,
            onTap: onTap,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            autovalidateMode: autovalidateMode,
            textCapitalization: textCapitalization,
            cursorColor: DP.green,
            style: style ?? DPText.body.copyWith(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              counterText: '',
              prefixText: prefixText,
              prefixStyle: DPText.body.copyWith(fontSize: 16, color: DP.ink),
              prefixIcon: prefix,
              suffixIcon: suffixWidget,
              errorMaxLines: 3,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 8),
            Text(helper!, style: DPText.small.copyWith(color: helperColor ?? DP.muted)),
          ],
        ],
      ),
    );
  }
}

/// A field-looking tappable box, used for pickers (country, provider, bank).
class DPSelectField extends StatelessWidget {
  final String? label;
  final String? value;
  final String hint;
  final VoidCallback? onTap;
  final Widget? leading;
  final DPIconData trailingIcon;
  final bool loading;
  final String? helper;
  final EdgeInsetsGeometry margin;

  const DPSelectField({
    super.key,
    this.label,
    this.value,
    this.hint = 'Select',
    this.onTap,
    this.leading,
    this.trailingIcon = DPIcons.chevronDown,
    this.loading = false,
    this.helper,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) DPFieldLabel(label!),
          Material(
            color: onTap == null ? DP.bg : DP.surface,
            borderRadius: BorderRadius.circular(DP.rMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(DP.rMd),
              onTap: loading ? null : onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DP.rMd),
                  border: Border.all(color: DP.border),
                ),
                child: Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 12)],
                    Expanded(
                      child: Text(
                        hasValue ? value! : hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DPText.body.copyWith(
                          fontSize: 16,
                          color: hasValue ? DP.ink : DP.faint,
                        ),
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      DPIcon(trailingIcon, size: 20, color: DP.muted),
                  ],
                ),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 8),
            Text(helper!, style: DPText.small),
          ],
        ],
      ),
    );
  }
}

/// Selectable pill used for networks, quick amounts, plan filters and tabs.
class DPChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final double height;
  final bool dense;

  const DPChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.leading,
    this.height = 46,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: height,
      decoration: BoxDecoration(
        color: selected ? DP.greenSoft : DP.surface,
        borderRadius: BorderRadius.circular(DP.rMd),
        border: Border.all(
          color: selected ? DP.green : DP.border,
          width: selected ? 1.3 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rMd),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DPText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: selected ? DP.green : DP.muted,
                      fontSize: dense ? 12.5 : 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Evenly spaced chips laid out in rows of [columns].
class DPChipGrid extends StatelessWidget {
  final List<String> labels;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final int columns;
  final double spacing;
  final double height;
  final EdgeInsetsGeometry margin;

  const DPChipGrid({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.columns = 3,
    this.spacing = 10,
    this.height = 46,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < labels.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        final idx = i + j;
        if (j > 0) cells.add(SizedBox(width: spacing));
        cells.add(Expanded(
          child: idx < labels.length
              ? DPChip(
                  label: labels[idx],
                  selected: selectedIndex == idx,
                  height: height,
                  dense: columns >= 4,
                  onTap: () => onSelected(idx),
                )
              : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Row(children: cells));
    }
    return Padding(padding: margin, child: Column(children: rows));
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

class DPCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;

  const DPCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.color = DP.surface,
    this.borderColor = DP.border,
    this.radius = DP.rLg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class DPSummaryRow {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;
  const DPSummaryRow(this.label, this.value, {this.valueColor, this.emphasize = false});
}

/// White card with label / value rows (fees, totals, balances).
class DPSummaryCard extends StatelessWidget {
  final List<DPSummaryRow> rows;
  final EdgeInsetsGeometry margin;
  final Widget? footer;

  const DPSummaryCard({
    super.key,
    required this.rows,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return DPCard(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.label,
                      style: DPText.bodyMuted.copyWith(
                        color: r.emphasize ? DP.ink : DP.muted,
                        fontWeight: r.emphasize ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      r.value,
                      textAlign: TextAlign.right,
                      style: DPText.value.copyWith(
                        color: r.valueColor ?? DP.ink,
                        fontWeight: r.emphasize ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

enum DPNoticeKind { success, info, warn, danger }

/// Soft tinted message with an icon.
class DPNotice extends StatelessWidget {
  final String text;
  final String? title;
  final DPNoticeKind kind;
  final DPIconData? icon;
  final EdgeInsetsGeometry margin;
  final Widget? action;

  const DPNotice(
    this.text, {
    super.key,
    this.title,
    this.kind = DPNoticeKind.success,
    this.icon,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    late DPIconData ic;
    switch (kind) {
      case DPNoticeKind.success:
        bg = DP.greenSoft;
        fg = DP.green;
        ic = DPIcons.shieldCheck;
        break;
      case DPNoticeKind.info:
        bg = DP.blueSoft;
        fg = DP.blue;
        ic = DPIcons.info;
        break;
      case DPNoticeKind.warn:
        bg = DP.warnSoft;
        fg = DP.warn;
        ic = DPIcons.circleAlert;
        break;
      case DPNoticeKind.danger:
        bg = DP.dangerSoft;
        fg = DP.danger;
        ic = DPIcons.triangleAlert;
        break;
    }
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DP.rMd + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: DPIcon(icon ?? ic, size: 19, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: DPText.label.copyWith(color: fg, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                ],
                Text(text, style: DPText.small.copyWith(color: fg, fontSize: 13, height: 1.45)),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Verified-account strip (e.g. "ADAEZE OKAFOR" under a meter number).
class DPVerifiedName extends StatelessWidget {
  final String name;
  final String? detail;
  final EdgeInsetsGeometry margin;
  const DPVerifiedName({
    super.key,
    required this.name,
    this.detail,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: DP.greenSoft,
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
      child: Row(
        children: [
          const DPIcon(DPIcons.circleCheck, size: 20, color: DP.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  style: DPText.label.copyWith(color: DP.green, fontWeight: FontWeight.w600),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: DPText.small.copyWith(color: DP.green)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lists, tiles, rows
// ---------------------------------------------------------------------------

/// Rounded white icon tile with a caption — the home & bills service grid.
class DPServiceTile extends StatelessWidget {
  final DPIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool disabled;
  final String? badge;

  const DPServiceTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.disabled = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DP.rLg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DP.surface,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: DP.border),
                  ),
                  child: DPIcon(icon, size: 24, color: disabled ? DP.faint : DP.green),
                ),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DP.navy,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontFamily: DP.font,
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: DPText.small.copyWith(
                color: disabled ? DP.faint : DP.ink,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Service tiles in a 4-column grid.
class DPServiceGrid extends StatelessWidget {
  final List<DPServiceTile> tiles;
  final int columns;
  const DPServiceGrid({super.key, required this.tiles, this.columns = 4});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            for (var j = 0; j < columns; j++)
              Expanded(child: i + j < tiles.length ? tiles[i + j] : const SizedBox()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

/// Soft square holding an icon (transaction rows, settings rows).
class DPIconBadge extends StatelessWidget {
  final DPIconData icon;
  final Color bg;
  final Color fg;
  final double size;
  final double radius;
  const DPIconBadge({
    super.key,
    required this.icon,
    this.bg = DP.blueSoft,
    this.fg = DP.blue,
    this.size = 44,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: DPIcon(icon, size: size * 0.46, color: fg),
    );
  }
}

class DPTransactionTile extends StatelessWidget {
  final DPIconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final bool credit;
  final bool failed;
  final VoidCallback? onTap;

  const DPTransactionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.credit = false,
    this.failed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DP.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            DPIconBadge(
              icon: icon,
              bg: credit ? DP.greenSoft : DP.blueSoft,
              fg: credit ? DP.green : DP.blue,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DPText.small.copyWith(
                        color: failed ? DP.danger : DP.muted,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              amount,
              style: DPText.value.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: failed ? DP.muted : (credit ? DP.green : DP.ink),
                decoration: failed ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings / menu row with icon, title, subtitle and chevron.
class DPMenuRow extends StatelessWidget {
  final DPIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color iconColor;
  final Color iconBg;
  final Color? titleColor;

  const DPMenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor = DP.blue,
    this.iconBg = DP.blueSoft,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DP.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            DPIconBadge(icon: icon, bg: iconBg, fg: iconColor, size: 40, radius: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DPText.body.copyWith(color: titleColor ?? DP.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: DPText.small),
                  ],
                ],
              ),
            ),
            trailing ?? const DPIcon(DPIcons.chevronRight, size: 18, color: DP.muted),
          ],
        ),
      ),
    );
  }
}

class DPStatusPill extends StatelessWidget {
  final String status;
  const DPStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg = DP.blueSoft, fg = DP.blue;
    if (s.contains('success') || s.contains('complete') || s.contains('deliver')) {
      bg = DP.greenSoft;
      fg = DP.green;
    } else if (s.contains('fail') || s.contains('reject') || s.contains('cancel')) {
      bg = DP.dangerSoft;
      fg = DP.danger;
    } else if (s.contains('pend') || s.contains('process')) {
      bg = DP.warnSoft;
      fg = DP.warn;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1),
        style: DPText.small.copyWith(color: fg, fontWeight: FontWeight.w500, fontSize: 11.5),
      ),
    );
  }
}

class DPAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  const DPAvatar({super.key, required this.name, this.size = 56, this.imageUrl});

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DP.greenSoft,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(),
            )
          : _initials(),
    );
  }

  Widget _initials() => Text(
        initials,
        style: TextStyle(
          fontFamily: DP.font,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: DP.green,
        ),
      );
}

// ---------------------------------------------------------------------------
// Feedback & states
// ---------------------------------------------------------------------------

class DPEmptyState extends StatelessWidget {
  final DPIconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DPEmptyState({
    super.key,
    this.icon = DPIcons.receipt,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DPIconBadge(icon: icon, size: 64, radius: 22, bg: DP.greenSoft, fg: DP.green),
          const SizedBox(height: 16),
          Text(title, style: DPText.section, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: DPText.bodyMuted, textAlign: TextAlign.center),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            DPButton(label: actionLabel!, onPressed: onAction, expand: false, height: 46),
          ],
        ],
      ),
    );
  }
}

class DPLoader extends StatelessWidget {
  final String? message;
  const DPLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: DP.green),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(message!, style: DPText.bodyMuted, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen dimmed overlay while a payment is processing.
class DPBusyOverlay extends StatelessWidget {
  final String message;
  const DPBusyOverlay({super.key, this.message = 'Processing…'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x66000000),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: DP.surface,
          borderRadius: BorderRadius.circular(DP.rLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: DP.green),
            ),
            const SizedBox(height: 16),
            Text(message, style: DPText.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Big round check used on success screens and dialogs.
class DPSuccessMark extends StatelessWidget {
  final double size;
  final bool failed;
  const DPSuccessMark({super.key, this.size = 76, this.failed = false});

  @override
  Widget build(BuildContext context) {
    final fg = failed ? DP.danger : DP.green;
    final soft = failed ? DP.dangerSoft : DP.greenSoft;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.62,
        height: size * 0.62,
        decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: DPIcon(failed ? DPIcons.x : DPIcons.check,
            size: size * 0.32, color: Colors.white, strokeWidth: 2.6),
      ),
    );
  }
}

/// Four (or six) boxes showing PIN / OTP progress.
class DPCodeBoxes extends StatelessWidget {
  final int length;
  final String value;
  final bool obscure;
  final bool error;
  final double boxSize;

  const DPCodeBoxes({
    super.key,
    required this.length,
    required this.value,
    this.obscure = true,
    this.error = false,
    this.boxSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(length, (i) {
        final filled = i < value.length;
        final active = i == value.length;
        return Container(
          width: boxSize,
          height: boxSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DP.surface,
            borderRadius: BorderRadius.circular(DP.rMd),
            border: Border.all(
              color: error
                  ? DP.danger
                  : active
                      ? DP.green
                      : DP.border,
              width: active || error ? 1.5 : 1,
            ),
          ),
          child: filled
              ? (obscure
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: DP.ink, shape: BoxShape.circle),
                    )
                  : Text(value[i], style: DPText.title.copyWith(fontSize: 22)))
              : null,
        );
      }),
    );
  }
}

/// On-screen number pad for PIN entry.
class DPKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? extraKey;

  const DPKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.extraKey,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Material(
              color: onTap == null ? Colors.transparent : DP.surface,
              borderRadius: BorderRadius.circular(DP.rMd + 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(DP.rMd + 2),
                onTap: onTap,
                child: SizedBox(height: 58, child: Center(child: child)),
              ),
            ),
          ),
        );
    Widget digit(String d) =>
        key(Text(d, style: DPText.title.copyWith(fontSize: 22, fontWeight: FontWeight.w500)), () {
          HapticFeedback.selectionClick();
          onDigit(d);
        });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: row.map(digit).toList()),
        Row(children: [
          key(extraKey ?? const SizedBox(), extraKey == null ? null : () {}),
          digit('0'),
          key(const DPIcon(DPIcons.arrowLeft, size: 22, color: DP.ink), () {
            HapticFeedback.selectionClick();
            onBackspace();
          }),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

class DPNavItem {
  final DPIconData icon;
  final String label;
  const DPNavItem(this.icon, this.label);
}

class DPBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<DPNavItem> items;

  const DPBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DP.surface,
        border: Border(top: BorderSide(color: DP.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DPIcon(
                          items[i].icon,
                          size: 23,
                          color: i == currentIndex ? DP.green : DP.muted,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          items[i].label,
                          style: DPText.small.copyWith(
                            fontSize: 11.5,
                            color: i == currentIndex ? DP.green : DP.muted,
                            fontWeight: i == currentIndex ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void dpSnack(BuildContext context, String message, {bool error = false, bool success = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? DP.danger : (success ? DP.green : DP.ink),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(
          children: [
            DPIcon(
              error ? DPIcons.circleAlert : (success ? DPIcons.circleCheck : DPIcons.info),
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Bottom sheet with the design's title row and padding.
Future<T?> showDPSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: DP.bg,
    builder: (ctx) {
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
            DP.gutter, 0, DP.gutter, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            if (scrollable)
              Flexible(child: SingleChildScrollView(child: builder(ctx)))
            else
              builder(ctx),
          ],
        ),
      );
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        child: content,
      );
    },
  );
}

/// One option row inside a picker sheet.
class DPOptionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;
  final String? trailingText;

  const DPOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.selected = false,
    required this.onTap,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? DP.greenSoft : DP.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rMd),
          side: BorderSide(color: selected ? DP.green : DP.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: DPText.body.copyWith(
                              color: selected ? DP.green : DP.ink,
                              fontWeight: FontWeight.w500)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: DPText.small),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null)
                  Text(trailingText!,
                      style: DPText.value.copyWith(color: selected ? DP.green : DP.ink)),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const DPIcon(DPIcons.circleCheck, size: 20, color: DP.green),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Naira formatting used across the redesign: ₦124,850.00
String dpNaira(num? value, {bool decimals = true}) {
  final v = (value ?? 0).toDouble();
  final neg = v < 0;
  final abs = v.abs();
  final fixed = abs.toStringAsFixed(decimals ? 2 : 0);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  final s = decimals ? '₦$intPart.${parts[1]}' : '₦$intPart';
  return neg ? '-$s' : s;
}

/// Code entry (OTP / PIN): shows boxes, captures digits with a hidden field.
class DPCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool obscure;
  final bool autofocus;
  final bool error;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  const DPCodeInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.obscure = false,
    this.autofocus = false,
    this.error = false,
    this.onCompleted,
    this.onChanged,
    this.focusNode,
  });

  @override
  State<DPCodeInput> createState() => _DPCodeInputState();
}

class _DPCodeInputState extends State<DPCodeInput> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final gap = widget.length > 4 ? 8.0 : 14.0;
      final box = ((c.maxWidth - gap * (widget.length - 1)) / widget.length).clamp(36.0, 64.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focus.requestFocus(),
        child: Stack(
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, v, __) => DPCodeBoxes(
                length: widget.length,
                value: v.text,
                obscure: widget.obscure,
                error: widget.error,
                boxSize: box,
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  maxLength: widget.length,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: (v) {
                    widget.onChanged?.call(v);
                    if (v.length == widget.length) widget.onCompleted?.call(v);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

enum DPDialogTone { success, error, warn, info }

/// Consistent result / confirmation dialog.
Future<T?> showDPDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  DPDialogTone tone = DPDialogTone.info,
  DPIconData? icon,
  List<String> bullets = const [],
  String primaryLabel = 'OK',
  VoidCallback? onPrimary,
  String? secondaryLabel,
  VoidCallback? onSecondary,
  bool barrierDismissible = true,
  Widget? body,
}) {
  late Color bg, fg;
  late DPIconData ic;
  switch (tone) {
    case DPDialogTone.success:
      bg = DP.greenSoft;
      fg = DP.green;
      ic = DPIcons.circleCheck;
      break;
    case DPDialogTone.error:
      bg = DP.dangerSoft;
      fg = DP.danger;
      ic = DPIcons.circleAlert;
      break;
    case DPDialogTone.warn:
      bg = DP.warnSoft;
      fg = DP.warn;
      ic = DPIcons.triangleAlert;
      break;
    case DPDialogTone.info:
      bg = DP.blueSoft;
      fg = DP.blue;
      ic = DPIcons.info;
      break;
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DPIconBadge(icon: icon ?? ic, bg: bg, fg: fg, size: 60, radius: 30),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: DPText.bodyMuted),
            ],
            if (body != null) ...[const SizedBox(height: 14), body],
            if (bullets.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: DPIcon(DPIcons.check, size: 15, color: DP.green),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(b, style: DPText.small.copyWith(fontSize: 13))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 22),
            DPButton(
              label: primaryLabel,
              onPressed: () {
                if (onPrimary != null) {
                  onPrimary();
                } else {
                  Navigator.of(ctx).pop();
                }
              },
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 10),
              DPButton.secondary(
                label: secondaryLabel,
                onPressed: () {
                  if (onSecondary != null) {
                    onSecondary();
                  } else {
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
