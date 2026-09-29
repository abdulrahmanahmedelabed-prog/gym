import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../data/gym_data.dart';
import '../../models/member.dart';
import '../../services/license.dart';
import '../../services/membership.dart';
import '../app_services.dart';
import '../theme.dart';
import 'upgrade.dart';

extension Ctx on BuildContext {
  GymData get gym => read<GymData>();
  GymData get gymWatch => watch<GymData>();
  AppServices get services => read<AppServices>();
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get wide => MediaQuery.sizeOf(this).width >= 840;

  void toast(String msg, {bool error = false}) {
    final m = ScaffoldMessenger.maybeOf(this);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? colors.error : null,
      duration: Duration(seconds: error ? 5 : 3),
    ));
  }

  Future<T?> push<T>(Widget page) => Navigator.of(this).push<T>(MaterialPageRoute(builder: (_) => page));
}

/// تنفيذ عملية مع إظهار الخطأ برسالة بدل تعطل الشاشة
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) context.toast(success);
    return r;
  } on LicenseException catch (e) {
    if (context.mounted) await showUpgradeDialog(context, feature: e.feature, message: e.message);
    return null;
  } catch (e) {
    if (context.mounted) context.toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, {String? message, String? ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok ?? tr('تأكيد')),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title,
    {String? initial, String? hint, bool number = false, int maxLines = 1, String? ok}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: maxLines,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok ?? tr('حفظ'))),
      ],
    ),
  );
  return r;
}

/// اختيار يوم. الافتراضي من 2000 إلى 2100، والتاريخ المبدئي يُحصر داخل المدى
/// (وإلا يتعطل منتقي التاريخ). [yearFirst] يبدأ باختيار السنة (لتاريخ الميلاد).
Future<DateTime?> pickDay(BuildContext context, DateTime initial, {DateTime? first, DateTime? last, bool yearFirst = false}) {
  final f = first ?? DateTime(2000);
  final l = last ?? DateTime(2100);
  final init = initial.isBefore(f) ? f : (initial.isAfter(l) ? l : initial);
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: f,
    lastDate: l,
    initialDatePickerMode: yearFirst ? DatePickerMode.year : DatePickerMode.day,
  );
}

/// تاريخ الميلاد: من 1920 حتى اليوم، ويبدأ باختيار السنة
Future<DateTime?> pickBirthDate(BuildContext context, DateTime? current, DateTime today) =>
    pickDay(context, current ?? DateTime(today.year - 25, today.month, today.day), first: DateTime(1920), last: today, yearFirst: true);

Future<TimeOfDay?> pickTime(BuildContext context, int minutes) =>
    showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

// -----------------------------------------------------------------------------
// عناصر عرض
// -----------------------------------------------------------------------------

({String label, Color color}) memberStateStyle(MemberState s) => switch (s) {
      MemberState.active => (label: tr('فعّال'), color: StatusColors.active),
      MemberState.expiring => (label: tr('ينتهي قريباً'), color: StatusColors.expiring),
      MemberState.frozen => (label: tr('مجمّد'), color: StatusColors.frozen),
      MemberState.pending => (label: tr('لم يبدأ'), color: StatusColors.pending),
      MemberState.expired => (label: tr('منتهي'), color: StatusColors.expired),
      MemberState.none => (label: tr('بدون اشتراك'), color: StatusColors.none),
    };

class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const Pill(this.label, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class StatePill extends StatelessWidget {
  final MemberState state;
  const StatePill(this.state, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = memberStateStyle(state);
    return Pill(s.label, s.color);
  }
}

class MemberAvatar extends StatelessWidget {
  final Member member;
  final double radius;
  final Color? ring;
  const MemberAvatar(this.member, {super.key, this.radius = 22, this.ring});

  @override
  Widget build(BuildContext context) {
    final photo = member.photo;
    final bg = member.gender == Gender.female ? const Color(0xFFFCE7F3) : const Color(0xFFE0F2FE);
    final fg = member.gender == Gender.female ? const Color(0xFFBE185D) : const Color(0xFF0369A1);
    Widget a = CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: photo == null ? null : MemoryImage(base64Decode(photo)),
      child: photo == null
          ? Text(member.name.isEmpty ? '?' : member.name.characters.first,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: radius * 0.8))
          : null,
    );
    if (ring != null) {
      a = Container(padding: const EdgeInsets.all(2.5), decoration: BoxDecoration(shape: BoxShape.circle, color: ring), child: a);
    }
    return a;
  }
}

class Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const Section({super.key, required this.title, this.trailing, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 0)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

class Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;
  const Kpi({super.key, required this.label, required this.value, required this.icon, required this.color, this.sub, this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                if (onTap != null) Icon(Icons.chevron_right, size: 18, color: context.colors.outline),
              ]),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(label, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (sub != null)
                Text(sub!, style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: context.colors.outline),
            const SizedBox(height: 12),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class MoneyText extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Color? color;
  const MoneyText(this.value, {super.key, this.style, this.color});
  @override
  Widget build(BuildContext context) =>
      Text(fmtMoney(value), style: (style ?? context.text.bodyMedium)?.copyWith(color: color, fontWeight: FontWeight.w700));
}

/// صف معلومة: عنوان وقيمة
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: context.colors.onSurfaceVariant))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
        ]),
      );
}

String fmtDay(DateTime d) => dayKey(d);

String relativeDays(int days) {
  if (days == 0) return tr('اليوم');
  if (days == 1) return tr('غداً');
  if (days == -1) return tr('أمس');
  return days > 0 ? tr('بعد {n} يوم', {'n': days}) : tr('منذ {n} يوم', {'n': -days});
}

/// شريط بحث
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final Widget? trailing;
  const SearchField({super.key, required this.controller, required this.hint, required this.onChanged, this.trailing});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? trailing
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  }),
        ),
      );
}

/// أزرار إجراءات دائرية صغيرة (اتصال، واتساب...)
class ActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const ActionCircle({super.key, required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

/// قائمة خيارات أسفل الشاشة
Future<T?> pickFromSheet<T>(BuildContext context, String title, List<(T, String, IconData?)> options) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: Theme.of(c).textTheme.titleMedium)),
          for (final o in options)
            ListTile(leading: o.$3 == null ? null : Icon(o.$3), title: Text(o.$2), onTap: () => Navigator.pop(c, o.$1)),
          const SizedBox(height: 8),
        ]),
      ),
    );

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final int minColumns;
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 160, this.spacing = 10, this.minColumns = 2});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        final cols = (box.maxWidth / minWidth).floor().clamp(minColumns, 6);
        final w = (box.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}
