// lib/ui/dp_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dp_motion.dart';
import 'dp_tokens.dart';

// ════════════════════════════════════════════════════════════
// Page chrome
// ════════════════════════════════════════════════════════════

/// Back button + title + optional green text action, as on every inner screen.
class DPTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final bool showBack;

  const DPTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          if (showBack) ...[
            DPIconSquare(
              icon: DPIcons.back,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              semanticLabel: 'Back',
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              style: DP.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null)
            DPTextLink(label: actionLabel!, onTap: onAction),
        ],
      ),
    );
  }
}

/// White rounded square with an icon (back button, header actions).
class DPIconSquare extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final Color background;
  final String? semanticLabel;
  final Widget? badge;

  const DPIconSquare({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.color = DP.ink,
    this.background = DP.surface,
    this.semanticLabel,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(DP.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rMd),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                if (badge != null) Positioned(top: 6, right: 6, child: badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DPTextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double fontSize;
  const DPTextLink({
    super.key,
    required this.label,
    this.onTap,
    this.color = DP.green,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Large friendly headline + muted subtitle ("Keep the conversation going.").
class DPHeadline extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double bottom;
  const DPHeadline(this.title, {super.key, this.subtitle, this.bottom = 24});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPAppear(child: Text(title, style: DP.display)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            DPAppear(
              delay: const Duration(milliseconds: 80),
              child: Text(subtitle!, style: DP.body.copyWith(color: DP.muted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Your everyday essentials ........ View all"
class DPSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  const DPSectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(top: 8, bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: DP.section)),
          if (actionLabel != null)
            DPTextLink(label: actionLabel!, onTap: onAction),
        ],
      ),
    );
  }
}

/// Small field label above an input.
class DPLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const DPLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: DP.label)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Muted helper line under a field ("Minimum ₦50 · Maximum ₦50,000").
class DPHelper extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const DPHelper(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? DP.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 15, color: c),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(text, style: DP.caption.copyWith(color: c))),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Buttons
// ════════════════════════════════════════════════════════════

class DPButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final IconData? leadingIcon;
  final Color background;
  final Color foreground;
  final double height;

  const DPButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.leadingIcon,
    this.background = DP.green,
    this.foreground = Colors.white,
    this.height = 56,
  });

  /// Mint button used on the navy balance card ("Add money").
  const DPButton.mint({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.leadingIcon,
    this.height = 52,
  })  : background = DP.mint,
        foreground = DP.navy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DPPressable(
      enabled: enabled,
      child: SizedBox(
      width: double.infinity,
      height: height,
      child: AnimatedContainer(
        duration: DPMotion.fast,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DP.rLg),
          boxShadow: enabled && background == DP.green
              ? const [
                  BoxShadow(
                    color: Color(0x33168566),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Material(
        color: enabled ? background : background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(DP.rLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rLg),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leadingIcon != null) ...[
                        Icon(leadingIcon, size: 20, color: foreground),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 10),
                        Icon(icon, size: 20, color: foreground),
                      ],
                    ],
                  ),
          ),
        ),
        ),
      ),
      ),
    );
  }
}

/// White button with a hairline border ("Back to home", "Log out").
class DPOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final double height;
  const DPOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = DP.ink,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return DPPressable(
      enabled: onPressed != null,
      child: SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: DP.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rLg),
          side: const BorderSide(color: DP.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rLg),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: onPressed == null ? DP.faint : color,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: color),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Bottom-anchored primary action with safe-area padding.
class DPBottomAction extends StatelessWidget {
  final Widget child;
  final Widget? footnote;
  const DPBottomAction({super.key, required this.child, this.footnote});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DP.bg,
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: DPAppear(
        delay: const Duration(milliseconds: 120),
        offsetY: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (footnote != null) ...[const SizedBox(height: 12), footnote!],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Inputs
// ════════════════════════════════════════════════════════════

/// White rounded text field with a hairline border and optional suffix icon.
/// Wraps [TextFormField] so existing validators, formatters and controllers
/// keep working unchanged.
class DPField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final Widget? prefix;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final TextStyle? style;
  final AutovalidateMode? autovalidateMode;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final int maxLines;

  const DPField({
    super.key,
    this.controller,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.prefix,
    this.prefixText,
    this.onChanged,
    this.validator,
    this.inputFormatters,
    this.maxLength,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
    this.style,
    this.autovalidateMode,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  static InputDecoration decoration({
    String? hint,
    Widget? suffix,
    Widget? prefix,
    String? prefixText,
    String? errorText,
  }) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DP.rMd),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DP.faint, fontSize: 16),
      filled: true,
      fillColor: DP.surface,
      isDense: false,
      counterText: '',
      errorText: errorText,
      errorMaxLines: 3,
      errorStyle: const TextStyle(color: DP.red, fontSize: 12.5),
      prefixText: prefixText,
      prefixStyle: const TextStyle(color: DP.ink, fontSize: 16),
      prefixIcon: prefix,
      suffixIcon: suffix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 8),
              child: suffix,
            ),
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIconColor: DP.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: b(DP.border),
      enabledBorder: b(DP.border),
      disabledBorder: b(DP.borderSoft),
      focusedBorder: b(DP.green, 1.4),
      errorBorder: b(DP.red),
      focusedErrorBorder: b(DP.red, 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      autovalidateMode: autovalidateMode,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      maxLines: obscureText ? 1 : maxLines,
      cursorColor: DP.green,
      style: style ?? const TextStyle(fontSize: 16, color: DP.ink),
      decoration: decoration(
        hint: hint,
        suffix: suffix,
        prefix: prefix,
        prefixText: prefixText,
        errorText: errorText,
      ),
    );
  }
}

/// Tappable field that looks like [DPField] but opens a picker
/// ("Ikeja Electric  ⌄").
class DPSelectField extends StatelessWidget {
  final String? value;
  final String hint;
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData trailingIcon;
  final bool enabled;
  const DPSelectField({
    super.key,
    required this.value,
    required this.hint,
    required this.onTap,
    this.leading,
    this.trailingIcon = DPIcons.chevronDown,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return Material(
      color: enabled ? DP.surface : DP.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rMd),
        side: const BorderSide(color: DP.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rMd),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  has ? value! : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: has ? DP.ink : DP.faint,
                  ),
                ),
              ),
              Icon(trailingIcon, color: DP.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet list picker matching the design system.
Future<T?> dpPickFromList<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  Widget Function(T)? leadingOf,
  T? selected,
  bool searchable = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DP.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DP.rXl)),
    ),
    builder: (ctx) => _DPPickerSheet<T>(
      title: title,
      items: items,
      labelOf: labelOf,
      subtitleOf: subtitleOf,
      leadingOf: leadingOf,
      selected: selected,
      searchable: searchable || items.length > 10,
    ),
  );
}

class _DPPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final Widget Function(T)? leadingOf;
  final T? selected;
  final bool searchable;
  const _DPPickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    this.subtitleOf,
    this.leadingOf,
    this.selected,
    required this.searchable,
  });

  @override
  State<_DPPickerSheet<T>> createState() => _DPPickerSheetState<T>();
}

class _DPPickerSheetState<T> extends State<_DPPickerSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items
            .where((e) => widget.labelOf(e).toLowerCase().contains(q))
            .toList();
    final maxH = MediaQuery.of(context).size.height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DPSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(widget.title, style: DP.title),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: DPField.decoration(
                    hint: 'Search',
                    suffix: const Icon(DPIcons.search),
                  ),
                ),
              ),
            Flexible(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nothing matches your search.',
                        textAlign: TextAlign.center,
                        style: DP.caption,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final item = list[i];
                        final sel = widget.selected != null &&
                            widget.labelOf(widget.selected as T) ==
                                widget.labelOf(item);
                        return Material(
                          color: sel ? DP.mint : DP.surface,
                          borderRadius: BorderRadius.circular(DP.rMd),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(DP.rMd),
                            onTap: () => Navigator.of(context).pop(item),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  if (widget.leadingOf != null) ...[
                                    widget.leadingOf!(item),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.labelOf(item),
                                          style: DP.body.copyWith(
                                            color: sel ? DP.green : DP.ink,
                                            fontWeight: sel
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                        if (widget.subtitleOf != null &&
                                            widget.subtitleOf!(item)
                                                .isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              widget.subtitleOf!(item),
                                              style: DP.caption,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (sel)
                                    const Icon(
                                      DPIcons.check,
                                      color: DP.green,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DPSheetHandle extends StatelessWidget {
  const DPSheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: DP.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Chips & selectors
// ════════════════════════════════════════════════════════════

/// Rounded selectable chip: white with hairline border, or mint with green
/// border when selected ("MTN", "₦2,000", "Prepaid meter").
class DPChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;
  final Widget? leading;
  final String? sublabel;

  const DPChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.height = 44,
    this.leading,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? DP.mint : DP.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rSm),
          side: BorderSide(
            color: selected ? DP.green : DP.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rSm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 6)],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? DP.green : DP.inkSoft,
                          ),
                        ),
                        if (sublabel != null)
                          Text(
                            sublabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DP.caption.copyWith(fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of equally wide chips (networks, tabs, filters).
class DPChipRow extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final double spacing;
  final double height;
  const DPChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.spacing = 10,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(
        Expanded(
          child: DPChip(
            label: options[i],
            selected: options[i] == selected,
            height: height,
            onTap: () => onSelect(options[i]),
          ),
        ),
      );
    }
    return Row(children: children);
  }
}

/// Wrap of chips laid out in a fixed number of columns (quick amounts).
class DPChipGrid extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final int columns;
  final double height;
  const DPChipGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.columns = 3,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var r = 0; r < options.length; r += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: 10));
        final i = r + c;
        cells.add(
          Expanded(
            child: i < options.length
                ? DPChip(
                    label: options[i],
                    selected: options[i] == selected,
                    height: height,
                    onTap: () => onSelect(options[i]),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: cells));
    }
    return Column(children: rows);
  }
}

/// Horizontally scrolling chip list for long option sets.
class DPChipScroller extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  const DPChipScroller({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => DPChip(
          label: options[i],
          selected: options[i] == selected,
          height: 42,
          onTap: () => onSelect(options[i]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Cards, banners, rows
// ════════════════════════════════════════════════════════════

class DPCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const DPCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = DP.surface,
    this.borderColor = DP.border,
    this.radius = 20,
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final body = Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
    final animated = DPAppear(
      child: onTap == null
          ? body
          : DPPressable(pressedScale: 0.985, child: body),
    );
    return margin == null
        ? animated
        : Padding(padding: margin!, child: animated);
  }
}

/// Label/value row inside a summary card ("Service fee ....... ₦0.00").
class DPSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;
  final Widget? trailing;
  const DPSummaryRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.strong = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: DP.body.copyWith(
                color: strong ? DP.ink : DP.muted,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                fontSize: 14.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: trailing ??
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: DP.body.copyWith(
                    color: valueColor ?? DP.ink,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14.5,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

enum DPTone { success, warning, info, error, navy }

/// Mint/amber/red info banner with a leading icon.
class DPBanner extends StatelessWidget {
  final String text;
  final DPTone tone;
  final IconData? icon;
  final String? title;
  final Widget? action;
  const DPBanner(
    this.text, {
    super.key,
    this.tone = DPTone.success,
    this.icon,
    this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    late IconData ic;
    switch (tone) {
      case DPTone.success:
        bg = DP.mint;
        fg = DP.green;
        ic = DPIcons.shieldCheck;
        break;
      case DPTone.warning:
        bg = DP.amberBg;
        fg = DP.amber;
        ic = DPIcons.info;
        break;
      case DPTone.info:
        bg = DP.blueTint;
        fg = DP.navyIcon;
        ic = DPIcons.info;
        break;
      case DPTone.error:
        bg = DP.redBg;
        fg = DP.red;
        ic = DPIcons.alert;
        break;
      case DPTone.navy:
        bg = DP.navy;
        fg = Colors.white;
        ic = DPIcons.info;
        break;
    }
    return DPAppear(
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DP.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? ic, size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      title!,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: TextStyle(color: fg, fontSize: 13.5, height: 1.45),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Rounded tinted square holding an icon (list leading, receipt hero).
class DPIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final double size;
  final double iconSize;
  const DPIconBadge(
    this.icon, {
    super.key,
    this.color = DP.green,
    this.background = DP.mint,
    this.size = 44,
    this.iconSize = 22,
  });

  /// Blue badge used for debits / neutral items.
  const DPIconBadge.blue(
    this.icon, {
    super.key,
    this.size = 44,
    this.iconSize = 22,
  })  : color = DP.navyIcon,
        background = DP.blueTint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

/// Generic list row: leading badge, title, subtitle, trailing.
class DPListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? titleColor;
  final int subtitleMaxLines;

  const DPListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
    this.titleColor,
    this.subtitleMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return DPAppear(
      offsetY: 8,
      duration: const Duration(milliseconds: 340),
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DP.rMd),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DP.body.copyWith(
                      fontSize: 15.5,
                      color: titleColor ?? DP.ink,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: DP.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
      ),
    );
  }
}

/// Settings-style row with chevron.
class DPMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;
  const DPMenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DPListRow(
      onTap: onTap,
      leading: DPIconBadge(
        icon,
        color: color ?? DP.navyIcon,
        background: color == null ? DP.blueTint : color!.withValues(alpha: 0.1),
        size: 40,
        iconSize: 20,
      ),
      title: title,
      titleColor: color,
      subtitle: subtitle,
      trailing: trailing ??
          const Icon(DPIcons.chevronRight, color: DP.muted, size: 22),
    );
  }
}

/// White square service tile with green line icon and label below.
class DPServiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool disabled;
  final String? tag;
  const DPServiceTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.disabled = false,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: DPPressable(
        enabled: onTap != null && !disabled,
        pressedScale: 0.92,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DP.rLg),
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
                    decoration: BoxDecoration(
                      color: DP.surface,
                      borderRadius: BorderRadius.circular(DP.rLg),
                      border: Border.all(color: DP.border),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: disabled ? DP.faint : DP.green,
                    ),
                  ),
                  if (tag != null)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: DP.amberBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: DP.amber,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: disabled ? DP.faint : DP.ink,
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

/// 4-column grid of [DPServiceTile]s.
class DPServiceGrid extends StatelessWidget {
  final List<DPServiceTile> tiles;
  final int columns;
  const DPServiceGrid({super.key, required this.tiles, this.columns = 4});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var r = 0; r < tiles.length; r += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final i = r + c;
        cells.add(
          Expanded(
            child: i < tiles.length
                ? DPAppear(
                    delay: DPMotion.stagger(i, stepMs: 40),
                    offsetY: 12,
                    scaleFrom: 0.9,
                    child: tiles[i],
                  )
                : const SizedBox(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      );
    }
    return Column(children: rows);
  }
}

/// Status word coloured by state: "Successful", "Pending", "Failed".
class DPStatus {
  DPStatus._();
  static Color colorFor(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('fail') ||
        s.contains('declin') ||
        s.contains('revers') ||
        s.contains('cancel')) {
      return DP.red;
    }
    if (s.contains('pend') || s.contains('process') || s.contains('initi')) {
      return DP.amber;
    }
    return DP.green;
  }

  static String labelFor(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.isEmpty) return 'Successful';
    if (s.contains('fail')) return 'Failed';
    if (s.contains('pend') || s.contains('process') || s.contains('initi')) {
      return 'Pending';
    }
    if (s.contains('revers') || s.contains('refund')) return 'Reversed';
    if (s.contains('cancel')) return 'Cancelled';
    if (s.contains('success') || s.contains('complet') || s.contains('deliver')) {
      return 'Successful';
    }
    final raw = status!;
    return raw[0].toUpperCase() + raw.substring(1);
  }
}

/// Empty state with icon, message and optional action.
class DPEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const DPEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return DPAppear(
      scaleFrom: 0.96,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          DPIconBadge(icon, size: 56, iconSize: 26),
          const SizedBox(height: 14),
          Text(title, style: DP.bodyStrong, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: DP.caption, textAlign: TextAlign.center),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            DPTextLink(label: actionLabel!, onTap: onAction),
          ],
        ],
      ),
      ),
    );
  }
}

/// Grey placeholder block for loading states.
class DPSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const DPSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DP.borderSoft,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Initials avatar ("AO").
class DPAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  const DPAvatar({super.key, required this.name, this.size = 56, this.imageUrl});

  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'D';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DP.mint,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: DP.green,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PIN / OTP
// ════════════════════════════════════════════════════════════

/// Read-only row of PIN boxes showing how many digits are entered.
class DPPinDots extends StatelessWidget {
  final int length;
  final int filled;
  final bool error;
  final bool obscure;
  final String? value;
  const DPPinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
    this.obscure = true,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final boxes = <Widget>[];
    for (var i = 0; i < length; i++) {
      final isFilled = i < filled;
      final isNext = i == filled;
      if (i > 0) boxes.add(const SizedBox(width: 10));
      boxes.add(
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DP.surface,
              borderRadius: BorderRadius.circular(DP.rMd),
              border: Border.all(
                color: error
                    ? DP.red
                    : (isNext ? DP.green : DP.border),
                width: isNext || error ? 1.5 : 1,
              ),
            ),
            child: isFilled
                ? (obscure || value == null || i >= value!.length
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: DP.ink,
                          shape: BoxShape.circle,
                        ),
                      )
                    : Text(
                        value![i],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: DP.ink,
                        ),
                      ))
                : null,
          ),
        ),
      );
    }
    return Row(children: boxes);
  }
}

/// PIN / OTP entry: boxes drawn over an invisible text field so the system
/// keyboard (and SMS/email autofill) keeps working. Uses the caller's
/// controller so existing verification logic is untouched.
class DPCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool obscure;
  final bool error;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  const DPCodeInput({
    super.key,
    required this.controller,
    this.length = 4,
    this.obscure = true,
    this.error = false,
    this.onCompleted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<DPCodeInput> createState() => _DPCodeInputState();
}

class _DPCodeInputState extends State<DPCodeInput> {
  late FocusNode _focus;
  bool _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focus = widget.focusNode!;
    } else {
      _focus = FocusNode();
      _ownsFocus = true;
    }
    widget.controller.addListener(_onText);
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focus.requestFocus(),
      child: Stack(
        children: [
          DPPinDots(
            length: widget.length,
            filled: text.length.clamp(0, widget.length),
            error: widget.error,
            obscure: widget.obscure,
            value: text,
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                showCursor: false,
                enableInteractiveSelection: false,
                autofillHints: widget.obscure
                    ? null
                    : const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
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
  }
}

/// On-screen numeric keypad for PIN screens.
class DPKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? leftAction;
  const DPKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leftAction,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Material(
              color: DP.surface,
              borderRadius: BorderRadius.circular(DP.rLg),
              child: InkWell(
                borderRadius: BorderRadius.circular(DP.rLg),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onDigit(d);
                },
                child: SizedBox(
                  height: 58,
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                        color: DP.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget row(List<String> ds) => Row(children: ds.map(key).toList());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(['1', '2', '3']),
        row(['4', '5', '6']),
        row(['7', '8', '9']),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 70,
                child: Center(child: leftAction ?? const SizedBox()),
              ),
            ),
            key('0'),
            Expanded(
              child: SizedBox(
                height: 70,
                child: Center(
                  child: IconButton(
                    onPressed: onBackspace,
                    icon: const Icon(
                      Icons.backspace_outlined,
                      color: DP.ink,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// Navigation bar
// ════════════════════════════════════════════════════════════

class DPNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  const DPNavItem(this.icon, this.label, {this.activeIcon});
}

class DPBottomNav extends StatelessWidget {
  final int index;
  final List<DPNavItem> items;
  final ValueChanged<int> onTap;
  const DPBottomNav({
    super.key,
    required this.index,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DP.surface,
        border: Border(top: BorderSide(color: DP.border)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final it = items[i];
          final active = i == index;
          final c = active ? DP.green : DP.muted;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: active ? 58 : 40,
                      height: 32,
                      decoration: BoxDecoration(
                        color: active ? DP.mint : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: AnimatedScale(
                        scale: active ? 1.08 : 1,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          active ? (it.activeIcon ?? it.icon) : it.icon,
                          color: c,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: DefaultTextStyle.of(context).style.merge(
                        TextStyle(
                          fontSize: 12,
                          color: c,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      child: Text(it.label),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Feedback
// ════════════════════════════════════════════════════════════

/// Floating snackbar in the design language.
void dpSnack(
  BuildContext context,
  String message, {
  bool error = false,
  bool success = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final Color bg = error ? DP.red : (success ? DP.green : DP.ink);
  final IconData ic =
      error ? DPIcons.alert : (success ? DPIcons.checkCircle : DPIcons.info);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rMd),
        ),
        content: Row(
          children: [
            Icon(ic, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Simple confirm / message dialog in the design language.
Future<bool?> dpDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  DPTone tone = DPTone.success,
  IconData? icon,
  bool destructive = false,
}) {
  late IconData ic;
  late Color c, bg;
  switch (tone) {
    case DPTone.error:
      ic = DPIcons.alert;
      c = DP.red;
      bg = DP.redBg;
      break;
    case DPTone.warning:
      ic = DPIcons.info;
      c = DP.amber;
      bg = DP.amberBg;
      break;
    case DPTone.info:
    case DPTone.navy:
      ic = DPIcons.info;
      c = DP.navyIcon;
      bg = DP.blueTint;
      break;
    case DPTone.success:
      ic = DPIcons.checkCircle;
      c = DP.green;
      bg = DP.mint;
      break;
  }
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: DP.bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rXl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DPIconBadge(icon ?? ic, color: c, background: bg, size: 56),
            const SizedBox(height: 16),
            Text(title, style: DP.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: DP.body.copyWith(color: DP.muted, fontSize: 14.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            DPButton(
              label: confirmLabel,
              height: 50,
              background: destructive ? DP.red : DP.green,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            if (cancelLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  cancelLabel,
                  style: const TextStyle(
                    color: DP.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
