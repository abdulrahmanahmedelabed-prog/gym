import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/phone.dart';
import '../../models/member.dart';
import '../../services/license.dart';
import '../widgets/common.dart';
import '../widgets/pay_widgets.dart';
import '../widgets/upgrade.dart';
import 'members_screen.dart';
import 'sale_screen.dart';

const leadSources = ['فيسبوك', 'إنستجرام', 'تيك توك', 'جوجل', 'صديق', 'مرّ من أمام النادي', 'أخرى'];

class MemberFormScreen extends StatefulWidget {
  final String? memberId;
  final String? presetName;
  final String? presetPhone;
  final Gender? presetGender;
  const MemberFormScreen({super.key, this.memberId, this.presetName, this.presetPhone, this.presetGender});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Member _m;
  late final bool _isNew;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _phone2 = TextEditingController();
  final _email = TextEditingController();
  final _nid = TextEditingController();
  final _address = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  final _medical = TextEditingController();
  final _notes = TextEditingController();
  bool _more = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = context.gym;
    final existing = g.members[widget.memberId];
    _isNew = existing == null;
    _m = existing ??
        context.services.members.newMember(name: widget.presetName ?? '', phone: widget.presetPhone ?? '', gender: widget.presetGender);
    _name.text = _m.name;
    _phone.text = _m.phone;
    _phone2.text = _m.phone2 ?? '';
    _email.text = _m.email ?? '';
    _nid.text = _m.nationalId ?? '';
    _address.text = _m.address ?? '';
    _emName.text = _m.emergencyName ?? '';
    _emPhone.text = _m.emergencyPhone ?? '';
    _medical.text = _m.medicalNotes ?? '';
    _notes.text = _m.notes ?? '';
  }

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _photo(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 320, maxHeight: 320, imageQuality: 70, preferredCameraDevice: CameraDevice.front);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _m.photo = base64Encode(bytes));
    } catch (e) {
      if (mounted) context.toast(tr('تعذر فتح الكاميرا'), error: true);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    _m
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..phone2 = _v(_phone2)
      ..email = _v(_email)
      ..nationalId = _v(_nid)
      ..address = _v(_address)
      ..emergencyName = _v(_emName)
      ..emergencyPhone = _v(_emPhone)
      ..medicalNotes = _v(_medical)
      ..notes = _v(_notes);
    final ms = context.services.members;
    final ok = await runAction(context, () async {
      if (_isNew) {
        await ms.addMember(_m);
      } else {
        await ms.updateMember(_m);
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != true) return;
    if (_isNew) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SaleScreen(memberId: _m.id, isNewMember: true)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final ref = g.members[_m.referredBy];
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? tr('عضو جديد') : tr('تعديل بيانات العضو'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_isNew ? tr('حفظ ومتابعة للاشتراك') : tr('حفظ')),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Stack(children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: context.colors.surfaceContainerHighest,
                backgroundImage: _m.photo == null ? null : MemoryImage(base64Decode(_m.photo!)),
                child: _m.photo == null ? Icon(Icons.person, size: 46, color: context.colors.outline) : null,
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: PopupMenuButton<ImageSource?>(
                  onSelected: (s) => s == null ? setState(() => _m.photo = null) : _photo(s),
                  itemBuilder: (_) => [
                    if (canScanWithCamera) PopupMenuItem(value: ImageSource.camera, child: Text(tr('التقاط صورة'))),
                    PopupMenuItem(value: ImageSource.gallery, child: Text(tr('من المعرض'))),
                    if (_m.photo != null) PopupMenuItem(value: null, child: Text(tr('حذف الصورة'))),
                  ],
                  child: CircleAvatar(radius: 16, backgroundColor: context.colors.primary, child: const Icon(Icons.camera_alt, size: 16, color: Colors.white)),
                ),
              ),
            ]),
          ),
          if (!_isNew)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('#${_m.code}', textAlign: TextAlign.center, style: context.text.titleMedium),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: '${tr('الاسم الكامل')} *', prefixIcon: const Icon(Icons.badge_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? tr('مطلوب') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: '${tr('الجوال (واتساب)')} *', prefixIcon: const Icon(Icons.phone_android)),
            validator: (v) => digitsOnly(v ?? '').length < 7 ? tr('رقم غير صحيح') : null,
          ),
          const SizedBox(height: 12),
          SegmentedButton<Gender?>(
            segments: [
              ButtonSegment(value: Gender.male, label: Text(tr('ذكر')), icon: const Icon(Icons.male)),
              ButtonSegment(value: Gender.female, label: Text(tr('أنثى')), icon: const Icon(Icons.female)),
            ],
            emptySelectionAllowed: true,
            selected: {if (_m.gender != null) _m.gender},
            onSelectionChanged: (v) => setState(() => _m.gender = v.isEmpty ? null : v.first),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await pickBirthDate(context, _m.birthDate, context.gym.today);
              if (d != null) setState(() => _m.birthDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: tr('تاريخ الميلاد (لتهنئة عيد الميلاد)'),
                prefixIcon: const Icon(Icons.cake_outlined),
                suffixIcon: _m.birthDate == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _m.birthDate = null)),
              ),
              child: Text(_m.birthDate == null ? '—' : dayKey(_m.birthDate!)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: leadSources.contains(_m.source) ? _m.source : null,
            decoration: InputDecoration(labelText: tr('كيف عرف النادي؟'), prefixIcon: const Icon(Icons.campaign_outlined)),
            items: [for (final s in leadSources) DropdownMenuItem(value: s, child: Text(tr(s)))],
            onChanged: (v) => _m.source = v,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_add_outlined),
            title: Text(tr('رشّحه عضو')),
            subtitle: Text(ref == null ? tr('لا أحد') : '${ref.name} (#${ref.code})'),
            trailing: ref == null ? const Icon(Icons.chevron_right) : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _m.referredBy = null)),
            onTap: () async {
              final picked = await context.push<Member>(const MembersScreen(pickOnly: true));
              if (picked != null && picked.id != _m.id) setState(() => _m.referredBy = picked.id);
            },
          ),
          const Divider(),
          Text(tr('الرسائل'), style: context.text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<Channel>(
            segments: [
              ButtonSegment(value: Channel.whatsapp, label: Text(tr('واتساب')), icon: const Icon(Icons.chat)),
              ButtonSegment(value: Channel.sms, label: Text(tr('رسالة SMS')), icon: const Icon(Icons.sms_outlined)),
            ],
            selected: {_m.channel},
            onSelectionChanged: (v) => setState(() => _m.channel = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: lockFor(context, Feature.autoRenew),
            title: Text(tr('تجديد تلقائي')),
            subtitle: Text(tr('قبل الانتهاء بأيام تُجهّز فاتورة التجديد وتُرسل له مع رمز الدفع، ويتجدد عند الدفع')),
            value: _m.autoRenew,
            onChanged: (v) async {
              if (v && !await ensureFeature(context, Feature.autoRenew)) return;
              setState(() => _m.autoRenew = v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('إيقاف رسائل التذكير والعروض')),
            subtitle: Text(tr('تُرسل له الفواتير وتذكير الأقساط فقط')),
            value: _m.optOut,
            onChanged: (v) => setState(() => _m.optOut = v),
          ),
          const Divider(),
          TextFormField(
            controller: _medical,
            decoration: InputDecoration(labelText: tr('ملاحظات صحية (تظهر عند الدخول)'), prefixIcon: const Icon(Icons.medical_information_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _notes, maxLines: 2, decoration: InputDecoration(labelText: tr('ملاحظات'), prefixIcon: const Icon(Icons.notes))),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _more = !_more),
            icon: Icon(_more ? Icons.expand_less : Icons.expand_more),
            label: Text(tr('بيانات إضافية')),
          ),
          if (_more) ...[
            TextFormField(controller: _phone2, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('جوال آخر'))),
            const SizedBox(height: 12),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('البريد الإلكتروني'))),
            const SizedBox(height: 12),
            TextFormField(controller: _nid, decoration: InputDecoration(labelText: tr('رقم الهوية'))),
            const SizedBox(height: 12),
            TextFormField(controller: _address, decoration: InputDecoration(labelText: tr('العنوان'))),
            const SizedBox(height: 12),
            TextFormField(controller: _emName, decoration: InputDecoration(labelText: tr('اسم شخص للطوارئ'))),
            const SizedBox(height: 12),
            TextFormField(controller: _emPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('هاتف الطوارئ'))),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
