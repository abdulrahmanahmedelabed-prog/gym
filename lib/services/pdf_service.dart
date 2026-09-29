import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/billing.dart';
import '../models/member.dart';
import 'reports.dart';

/// رمز QR للفاتورة الضريبية المبسطة في السعودية (المرحلة الأولى): TLV مشفّر Base64
String zatcaTlv({
  required String seller,
  required String vatNumber,
  required DateTime time,
  required double total,
  required double vat,
}) {
  final out = BytesBuilder();
  final values = [seller, vatNumber, '${time.toUtc().toIso8601String().split('.').first}Z', total.toStringAsFixed(2), vat.toStringAsFixed(2)];
  for (var i = 0; i < values.length; i++) {
    var b = utf8.encode(values[i]);
    if (b.length > 255) b = b.sublist(0, 255);
    out
      ..addByte(i + 1)
      ..addByte(b.length)
      ..add(b);
  }
  return base64Encode(out.toBytes());
}

/// حذف الرموز التعبيرية (خط PDF لا يحتويها)
String pdfSafe(String s) => s.replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '').trim();

class PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  PdfFonts(this.regular, this.bold);

  factory PdfFonts.fromBytes(ByteData regular, ByteData bold) => PdfFonts(pw.Font.ttf(regular), pw.Font.ttf(bold));
}

class PdfService {
  final GymData d;
  final PdfFonts fonts;
  PdfService(this.d, this.fonts);

  pw.ThemeData get _theme => pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);

  pw.TextDirection get _dir => I18n.isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  pw.Widget _t(String s, {double size = 10, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textDirection: _dir,
        textAlign: align,
        style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
      );

  pw.Widget _row(String label, String value, {bool bold = false, double size = 10}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [_t(label, bold: bold, size: size), _t(value, bold: bold, size: size)],
        ),
      );

  static final _accent = PdfColor.fromInt(0xFF0F766E);

  /// فاتورة PDF (A4 أو إيصال حراري 80مم)
  Future<Uint8List> invoice(Invoice inv, {bool? thermal}) async {
    thermal ??= d.settings.receiptThermal;
    final s = d.settings;
    final m = d.members[inv.memberId];
    final doc = pw.Document(title: inv.number, author: s.gymName, theme: _theme);
    final pays = d.paymentsOf(inv.id).toList()..sort((a, b) => a.date.compareTo(b.date));
    final small = thermal ? 8.0 : 10.0;
    pw.MemoryImage? logo;
    if (s.logo != null) {
      try {
        logo = pw.MemoryImage(base64Decode(s.logo!));
      } catch (_) {}
    }
    String? zatca;
    if (s.zatcaQr && inv.taxRate > 0 && s.taxNumber.isNotEmpty) {
      zatca = zatcaTlv(seller: s.gymName, vatNumber: s.taxNumber, time: inv.date, total: inv.total, vat: inv.tax);
    }
    String? payLink;
    for (final l in inv.links.reversed) {
      if (l.status == LinkStatus.pending && inv.balance > 0) {
        payLink = l.url;
        break;
      }
    }
    final title = inv.taxRate > 0 ? tr('فاتورة ضريبية مبسطة') : tr('فاتورة');

    final header = pw.Column(
      crossAxisAlignment: thermal ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) pw.Image(logo, height: thermal ? 40 : 56),
        _t(s.gymName, size: thermal ? 13 : 18, bold: true, color: _accent),
        if (s.address.isNotEmpty) _t(s.address, size: small),
        if (s.gymPhone.isNotEmpty) _t(s.gymPhone, size: small),
        if (inv.taxRate > 0 && s.taxNumber.isNotEmpty) _t('${tr('الرقم الضريبي')}: ${s.taxNumber}', size: small),
      ],
    );

    final info = pw.Column(children: [
      _row(title, inv.number, bold: true, size: thermal ? 10 : 12),
      _row(tr('التاريخ'), '${dayKey(inv.date)} ${hhmm(minutesOfDay(inv.date))}', size: small),
      if (m != null) _row(tr('العضو'), '${m.name} (#${m.code})', size: small),
      if (m == null && inv.customerName != null) _row(tr('العميل'), inv.customerName!, size: small),
      if (m != null && m.phone.isNotEmpty) _row(tr('الجوال'), m.phone, size: small),
      if (inv.voided) _row(tr('الحالة'), tr('ملغاة'), bold: true, size: small),
    ]);

    final items = pw.TableHelper.fromTextArray(
      context: null,
      headerDirection: _dir,
      tableDirection: _dir,
      headers: [tr('البند'), tr('الكمية'), tr('السعر'), tr('الإجمالي')].map(pdfSafe).toList(),
      data: [
        for (final i in inv.items) [pdfSafe(i.description), fmtNum(i.qty), fmtMoney(i.unitPrice, symbol: false), fmtMoney(i.total, symbol: false)],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: small, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _accent),
      cellStyle: pw.TextStyle(fontSize: small),
      cellAlignment: pw.Alignment.center,
      columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)},
      cellAlignments: {0: I18n.isAr ? pw.Alignment.centerRight : pw.Alignment.centerLeft},
    );

    final totals = pw.Column(children: [
      _row(tr('المجموع'), fmtMoney(inv.subtotal), size: small),
      if (inv.discount > 0) _row(tr('الخصم'), '- ${fmtMoney(inv.discount)}', size: small),
      if (inv.taxRate > 0)
        _row('${tr('الضريبة')} ${fmtNum(inv.taxRate * 100)}%${inv.taxInclusive ? ' (${tr('شاملة')})' : ''}', fmtMoney(inv.tax),
            size: small),
      pw.Divider(thickness: 0.5),
      _row(tr('الإجمالي'), fmtMoney(inv.total), bold: true, size: thermal ? 11 : 13),
      _row(tr('المدفوع'), fmtMoney(inv.paid), size: small),
      if (inv.balance > 0) _row(tr('المتبقي'), fmtMoney(inv.balance), bold: true, size: small),
    ]);

    final inst = inv.installments.isEmpty
        ? null
        : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.SizedBox(height: 8),
            _t(tr('جدول الأقساط'), bold: true, size: small),
            for (final x in inv.installmentStatus())
              _row(dayKey(x.inst.due), x.left <= 0 ? '${fmtMoney(x.inst.amount)} ✓' : fmtMoney(x.inst.amount), size: small),
          ]);

    final payList = pays.isEmpty
        ? null
        : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.SizedBox(height: 8),
            _t(tr('الدفعات'), bold: true, size: small),
            for (final p in pays)
              _row('${dayKey(p.date)} — ${payMethodName(p.method)}${p.reference == null ? '' : ' (${p.reference})'}',
                  fmtMoney(p.amount), size: small),
          ]);

    final qrs = pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      if (zatca != null)
        pw.Column(children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: zatca, width: thermal ? 70 : 90, height: thermal ? 70 : 90),
        ]),
      if (zatca != null && payLink != null) pw.SizedBox(width: 24),
      if (payLink != null)
        pw.Column(children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: payLink, width: thermal ? 70 : 90, height: thermal ? 70 : 90),
          _t(tr('امسح للدفع'), size: small),
        ]),
    ]);

    final footer = s.invoiceFooter.isEmpty ? null : _t(s.invoiceFooter, size: small, align: pw.TextAlign.center);

    final body = <pw.Widget>[
      header,
      pw.SizedBox(height: 10),
      info,
      pw.SizedBox(height: 10),
      items,
      pw.SizedBox(height: 8),
      thermal ? totals : pw.Row(children: [pw.Expanded(flex: 3, child: pw.SizedBox()), pw.Expanded(flex: 2, child: totals)]),
      ?inst,
      ?payList,
      if (zatca != null || payLink != null) ...[pw.SizedBox(height: 12), qrs],
      if (footer != null) ...[pw.SizedBox(height: 12), pw.Center(child: footer)],
    ];

    if (thermal) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 8, marginRight: 8, marginTop: 8, marginBottom: 8),
        textDirection: _dir,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: body),
      ));
    } else {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
        textDirection: _dir,
        build: (_) => body,
      ));
    }
    return doc.save();
  }

  /// بطاقة عضوية للطباعة (مقاس البطاقة البنكية) برمز QR
  Future<Uint8List> memberCard(Member m, {String? subtitle}) async {
    final s = d.settings;
    final doc = pw.Document(title: '${m.name} — ${s.gymName}', theme: _theme);
    pw.MemoryImage? photo;
    if (m.photo != null) {
      try {
        photo = pw.MemoryImage(base64Decode(m.photo!));
      } catch (_) {}
    }
    const card = PdfPageFormat(85.6 * PdfPageFormat.mm, 54 * PdfPageFormat.mm, marginAll: 8);
    doc.addPage(pw.Page(
      pageFormat: card,
      textDirection: _dir,
      build: (_) => pw.Row(children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _t(s.gymName, bold: true, size: 11, color: _accent),
            pw.SizedBox(height: 6),
            if (photo != null) pw.ClipOval(child: pw.Image(photo, width: 34, height: 34, fit: pw.BoxFit.cover)),
            _t(m.name, bold: true, size: 10),
            _t('#${m.code}', size: 9),
            if (subtitle != null) _t(subtitle, size: 7),
          ]),
        ),
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: m.qrData, width: 72, height: 72),
      ]),
    ));
    return doc.save();
  }

  /// تقرير الفترة PDF
  Future<Uint8List> periodReport(Range r) async {
    final rep = Reports(d);
    final s = d.settings;
    final doc = pw.Document(title: tr('تقرير الفترة'), theme: _theme);
    final byMethod = rep.collectedByMethod(r);
    final byKind = rep.salesByKind(r);
    final exp = rep.expensesByCategory(r);
    final sold = rep.subsSold(r);
    final ren = rep.renewalRate(r);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
      textDirection: _dir,
      build: (_) => [
        _t(s.gymName, size: 18, bold: true, color: _accent),
        _t('${tr('تقرير الفترة')}: ${dayKey(r.from)} → ${dayKey(r.to)}', size: 12, bold: true),
        pw.SizedBox(height: 12),
        _row(tr('المحصّل'), fmtMoney(rep.collected(r)), bold: true),
        for (final e in byMethod.entries) _row('   ${payMethodName(e.key)}', fmtMoney(e.value)),
        _row(tr('المبيعات (قيمة الفواتير)'), fmtMoney(rep.sales(r))),
        for (final e in byKind.entries) _row('   ${itemKindName(e.key)}', fmtMoney(e.value)),
        if (rep.taxCollected(r) > 0) _row(tr('الضريبة'), fmtMoney(rep.taxCollected(r))),
        _row(tr('المصروفات'), fmtMoney(rep.expenses(r))),
        for (final e in exp.entries) _row('   ${e.key}', fmtMoney(e.value)),
        pw.Divider(),
        _row(tr('صافي الربح النقدي'), fmtMoney(rep.net(r)), bold: true),
        pw.SizedBox(height: 12),
        _row(tr('أعضاء جدد'), '${rep.newMembers(r)}'),
        _row(tr('اشتراكات جديدة / تجديد'), '${sold.fresh} / ${sold.renewals}'),
        _row(tr('نسبة التجديد'), '${(ren.rate * 100).toStringAsFixed(0)}% (${ren.renewed}/${ren.ended})'),
        _row(tr('الزيارات'), '${rep.dailyVisits(r).fold(0, (s, x) => s + x.count)}'),
        _row(tr('الأعضاء الفعّالون اليوم'), '${rep.activeCount()}'),
      ],
    ));
    return doc.save();
  }
}
