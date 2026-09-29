import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../models/activity.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../models/settings.dart';
import '../../services/membership.dart';
import '../../services/templates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'member_detail_screen.dart';
import 'settings_screen.dart';

String reminderKindName(String k) => switch (k) {
      Rk.welcome => tr('ترحيب'),
      Rk.receipt => tr('إيصال دفع'),
      Rk.expirySoon => tr('قرب الانتهاء'),
      Rk.expired => tr('انتهاء الاشتراك'),
      Rk.winback => tr('استرجاع'),
      Rk.visitsLow => tr('حصص قليلة'),
      Rk.installmentDue => tr('قسط قادم'),
      Rk.installmentLate => tr('قسط متأخر'),
      Rk.birthday => tr('عيد ميلاد'),
      Rk.inactive => tr('غياب'),
      Rk.freezeEnd => tr('نهاية التجميد'),
      Rk.classReminder => tr('تذكير حصة'),
      Rk.ownerDaily => tr('ملخص للمالك'),
      'invoice' => tr('فاتورة'),
      'campaign' => tr('حملة'),
      _ => tr('رسالة'),
    };

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with WidgetsBindingObserver {
  bool _sequential = false; // وضع الإرسال المتتالي: بعد العودة من واتساب يُفتح التالي
  int _sentInRun = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sequential) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _sequential) _sendNext();
      });
    }
  }

  List<Message> _pending() =>
      context.gym.messages.all.where((m) => m.status == MsgStatus.manual).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> _sendNext() async {
    final list = _pending();
    if (list.isEmpty) {
      setState(() => _sequential = false);
      context.toast(tr('أُرسلت كل الرسائل ({n}) ✓', {'n': _sentInRun}));
      return;
    }
    final sv = context.services;
    try {
      await sv.openManual(list.first);
      _sentInRun++;
    } catch (e) {
      setState(() => _sequential = false);
      if (mounted) context.toast(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final pending = _pending();
    final queued = g.messages.all.where((m) => m.status == MsgStatus.queued || m.status == MsgStatus.failed).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sent = g.messages.all.where((m) => m.status == MsgStatus.sent).toList()..sort((a, b) => (b.sentAt ?? b.createdAt).compareTo(a.sentAt ?? a.createdAt));
    final autoWa = sv.dispatcher.isAuto(Channel.whatsapp);
    final autoSms = sv.dispatcher.isAuto(Channel.sms);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('الرسائل والتذكيرات')),
          actions: [
            IconButton(
              tooltip: tr('فحص التذكيرات الآن'),
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                final n = await runAction(context, () => sv.reminders.run(force: true));
                if (n != null && context.mounted) context.toast(tr('{n} تذكير جديد', {'n': n}));
                await sv.dispatcher.dispatchQueued();
              },
            ),
            IconButton(
              tooltip: tr('إعدادات الرسائل'),
              icon: const Icon(Icons.tune),
              onPressed: () => context.push(const MessagingSettingsScreen()),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: '${tr('جاهزة')} (${pending.length})'),
            Tab(text: '${tr('آلية/فشلت')} (${queued.length})'),
            Tab(text: tr('المرسلة')),
          ]),
        ),
        floatingActionButton: g.can(Perm.campaigns)
            ? FloatingActionButton.extended(
                heroTag: 'campaign',
                onPressed: () => context.push(const CampaignScreen()),
                icon: const Icon(Icons.campaign),
                label: Text(tr('رسالة جماعية')),
              )
            : null,
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Card(
              margin: const EdgeInsets.all(16),
              color: context.colors.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(autoWa ? Icons.bolt : Icons.touch_app_outlined, color: context.colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        autoWa
                            ? tr('واتساب يُرسل آلياً عبر المزوّد. الرسائل هنا لأعضاء اختاروا SMS أو لتعذر الإرسال.')
                            : tr('التذكيرات تُجهّز تلقائياً كل يوم. اضغط «إرسال الكل» وسيفتح واتساب لكل عضو والرسالة جاهزة — اضغط إرسال ثم ارجع للتطبيق ليفتح التالي.'),
                      ),
                    ),
                  ]),
                  if (!autoWa || !autoSms)
                    TextButton(
                      onPressed: () => context.push(const MessagingSettingsScreen()),
                      child: Text(tr('فعّل الإرسال الآلي الكامل (بدون لمس)')),
                    ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _sequential
                        ? OutlinedButton.icon(onPressed: () => setState(() => _sequential = false), icon: const Icon(Icons.stop), label: Text(tr('إيقاف الإرسال المتتالي')))
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                            onPressed: () {
                              setState(() {
                                _sequential = true;
                                _sentInRun = 0;
                              });
                              _sendNext();
                            },
                            icon: const Icon(Icons.send),
                            label: Text(tr('إرسال الكل ({n})', {'n': pending.length})),
                          ),
                  ],
                ]),
              ),
            ),
            if (pending.isEmpty) EmptyState(icon: Icons.mark_chat_read_outlined, title: tr('لا رسائل تنتظر الإرسال')),
            for (final m in pending) _MsgTile(msg: m),
          ]),
          queued.isEmpty
              ? EmptyState(icon: Icons.bolt, title: tr('لا رسائل في الانتظار'))
              : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        for (final m in queued.where((m) => m.status == MsgStatus.failed)) {
                          m
                            ..status = MsgStatus.queued
                            ..attempts = 0;
                          await g.put(m);
                        }
                        final r = await sv.dispatcher.dispatchQueued(force: true);
                        if (context.mounted) context.toast(tr('أُرسلت {s} • فشلت {f}', {'s': r.sent, 'f': r.failed}));
                      },
                      icon: const Icon(Icons.send),
                      label: Text(tr('أرسل الآن')),
                    ),
                  ),
                  for (final m in queued) _MsgTile(msg: m),
                ]),
          sent.isEmpty
              ? EmptyState(icon: Icons.outbox, title: tr('لم تُرسل رسائل بعد'))
              : ListView(padding: const EdgeInsets.only(bottom: 96), children: [for (final m in sent.take(300)) _MsgTile(msg: m)]),
        ]),
      ),
    );
  }
}

class _MsgTile extends StatelessWidget {
  final Message msg;
  const _MsgTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final sv = context.services;
    final m = g.members[msg.memberId];
    final wa = msg.channel == Channel.whatsapp;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (m != null) MemberAvatar(m, radius: 16) else const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: m == null ? null : () => context.push(MemberDetailScreen(memberId: m.id)),
                child: Text(msg.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            Pill(reminderKindName(msg.kind), brandSeed),
            const SizedBox(width: 6),
            Icon(wa ? Icons.chat : Icons.sms_outlined, size: 18, color: wa ? const Color(0xFF25D366) : const Color(0xFF0EA5E9)),
          ]),
          const SizedBox(height: 6),
          Text(msg.body, maxLines: 4, overflow: TextOverflow.ellipsis),
          if (msg.error != null && msg.status != MsgStatus.sent)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(msg.error!, style: TextStyle(color: context.colors.error, fontSize: 12), maxLines: 2)),
          Row(children: [
            Text(
              msg.status == MsgStatus.sent ? '${tr('أُرسلت')} ${dayKey(msg.sentAt ?? msg.createdAt)}' : dayKey(msg.createdAt),
              style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
            ),
            const Spacer(),
            if (msg.status != MsgStatus.sent) ...[
              IconButton(
                tooltip: tr('إلغاء'),
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  msg.status = MsgStatus.cancelled;
                  await g.put(msg);
                },
              ),
              IconButton(
                tooltip: wa ? tr('إرسال بـ SMS بدلاً من واتساب') : tr('إرسال بواتساب بدلاً من SMS'),
                icon: Icon(wa ? Icons.sms_outlined : Icons.chat, size: 20),
                onPressed: () async {
                  msg.channel = wa ? Channel.sms : Channel.whatsapp;
                  msg.status = sv.dispatcher.isAuto(msg.channel) ? MsgStatus.queued : MsgStatus.manual;
                  await g.put(msg);
                },
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final r = await runAction(context, () => sv.send(msg));
                  if (r != null && context.mounted) context.toast(r);
                },
                icon: const Icon(Icons.send, size: 18),
                label: Text(tr('إرسال')),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الرسائل الجماعية
// -----------------------------------------------------------------------------

enum Segment { active, expiring, expired, frozen, debt, inactive, women, men, birthdayMonth, all, leads }

String segmentName(Segment s) => switch (s) {
      Segment.active => tr('الأعضاء الفعّالون'),
      Segment.expiring => tr('ينتهي اشتراكهم خلال 7 أيام'),
      Segment.expired => tr('منتهي خلال آخر 60 يوماً'),
      Segment.frozen => tr('المجمّدون'),
      Segment.debt => tr('عليهم مبالغ'),
      Segment.inactive => tr('فعّالون لم يحضروا منذ 14 يوماً'),
      Segment.women => tr('السيدات الفعّالات'),
      Segment.men => tr('الرجال الفعّالون'),
      Segment.birthdayMonth => tr('أعياد ميلاد هذا الشهر'),
      Segment.all => tr('كل الأعضاء'),
      Segment.leads => tr('العملاء المحتملون'),
    };

class CampaignScreen extends StatefulWidget {
  const CampaignScreen({super.key});
  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen> {
  Segment _seg = Segment.expired;
  String? _planId;
  final _text = TextEditingController(text: 'مرحباً {first_name} 👋\n');
  Channel? _channel; // null = حسب تفضيل كل عضو
  bool _sending = false;

  List<({Member? m, Lead? l})> _targets() {
    final g = context.gym;
    final ms = context.services.members;
    final today = g.today;
    if (_seg == Segment.leads) {
      return [for (final l in g.leads.all.where((l) => l.status != LeadStatus.won && l.status != LeadStatus.lost)) (m: null, l: l)];
    }
    final out = <({Member? m, Lead? l})>[];
    for (final m in g.members.all) {
      if (m.archived || m.optOut) continue;
      final st = ms.stateOf(m.id);
      final sub = ms.currentSub(m.id);
      if (_planId != null && sub?.planId != _planId) continue;
      final active = st == MemberState.active || st == MemberState.expiring;
      final ok = switch (_seg) {
        Segment.active => active,
        Segment.expiring => st == MemberState.expiring,
        Segment.expired => st == MemberState.expired && sub != null && daysBetween(sub.end, today) <= 60,
        Segment.frozen => st == MemberState.frozen,
        Segment.debt => g.balanceOf(m.id) > 0,
        Segment.inactive => active && daysBetween(g.lastVisit(m.id)?.time ?? sub!.start, today) >= 14,
        Segment.women => active && m.gender == Gender.female,
        Segment.men => active && m.gender == Gender.male,
        Segment.birthdayMonth => m.birthDate?.month == today.month,
        Segment.all => true,
        Segment.leads => false,
      };
      if (ok) out.add((m: m, l: null));
    }
    return out;
  }

  Future<void> _send() async {
    final targets = _targets();
    if (targets.isEmpty || _text.text.trim().isEmpty) return;
    final ok = await confirm(context, tr('إرسال لـ {n} شخص؟', {'n': targets.length}));
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    final g = context.gym;
    final sv = context.services;
    final ctx = TemplateContext(g);
    final msgs = <Message>[];
    for (final t in targets) {
      Message? msg;
      if (t.m != null) {
        final sub = sv.members.currentSub(t.m!.id);
        final vars = sub == null ? ctx.base(t.m) : ctx.forSub(t.m!, sub);
        msg = sv.reminders.build(member: t.m, kind: 'campaign', body: renderTemplate(_text.text, vars), channel: _channel);
      } else {
        final l = t.l!;
        msg = sv.reminders.build(
            phone: l.phone, name: l.name, leadId: l.id, kind: 'campaign',
            body: renderTemplate(_text.text, {...ctx.base(null), 'name': l.name, 'first_name': l.name.split(' ').first}),
            channel: _channel);
      }
      if (msg != null) msgs.add(msg);
    }
    await g.putAll(msgs);
    await g.log('campaign', '${segmentName(_seg)}: ${msgs.length}');
    await sv.dispatcher.dispatchQueued(force: true);
    if (!mounted) return;
    setState(() => _sending = false);
    context.toast(tr('جُهّزت {n} رسالة', {'n': msgs.length}));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final targets = _targets();
    final sample = targets.isEmpty ? null : targets.first;
    final ctx = TemplateContext(g);
    String preview = '';
    if (sample?.m != null) {
      final sub = context.services.members.currentSub(sample!.m!.id);
      preview = renderTemplate(_text.text, sub == null ? ctx.base(sample.m) : ctx.forSub(sample.m!, sub));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('رسالة جماعية'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: targets.isEmpty || _sending ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(tr('إرسال إلى {n}', {'n': targets.length})),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('إلى من؟'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in Segment.values) ChoiceChip(label: Text(segmentName(s)), selected: _seg == s, onSelected: (_) => setState(() => _seg = s)),
        ]),
        const SizedBox(height: 12),
        if (_seg != Segment.leads)
          DropdownButtonFormField<String?>(
            initialValue: _planId,
            decoration: InputDecoration(labelText: tr('باقة محددة (اختياري)')),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('كل الباقات'))),
              for (final p in g.plans.all) DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _planId = v),
          ),
        const SizedBox(height: 16),
        Text(tr('الرسالة'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(controller: _text, maxLines: 6, minLines: 4, onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in ['{first_name}', '{plan}', '{end_date}', '{balance}', '{gym}', '{gym_phone}', '{pay_link}'])
            ActionChip(
              label: Text(v, style: const TextStyle(fontSize: 12)),
              onPressed: () => setState(() {
                _text.text += v;
              }),
            ),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<Channel?>(
          segments: [
            ButtonSegment(value: null, label: Text(tr('حسب تفضيل العضو'))),
            ButtonSegment(value: Channel.whatsapp, label: Text(tr('واتساب'))),
            ButtonSegment(value: Channel.sms, label: Text(tr('SMS'))),
          ],
          selected: {_channel},
          onSelectionChanged: (v) => setState(() => _channel = v.first),
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('معاينة'), style: context.text.titleSmall),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
            child: Text(preview, style: const TextStyle(color: Colors.black87)),
          ),
        ],
        const SizedBox(height: 12),
        Text(tr('الأعضاء الذين أوقفوا الرسائل لا يُرسل لهم.'), style: context.text.bodySmall),
      ]),
    );
  }
}

