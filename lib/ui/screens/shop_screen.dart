import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/billing.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../services/billing.dart';
import '../../services/membership.dart';
import '../../services/reports.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart';
import 'members_screen.dart';

/// متجر النادي: بيع سريع للمياه والمكملات مع مخزون
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _cart = <String, CartLine>{};
  final _q = TextEditingController();
  Member? _member;
  PayMethod _method = PayMethod.cash;

  /// الإجمالي كما في الفاتورة (مع الضريبة المضافة إن كانت الأسعار غير شاملة لها)
  double get _total => context.services.members.totalWithTax(_cart.values.fold(0.0, (s, l) => s + l.total));

  void _add(Product p) {
    setState(() {
      final l = _cart[p.id];
      if (l == null) {
        _cart[p.id] = CartLine(p);
      } else {
        l.qty++;
      }
    });
  }

  Future<void> _checkout({bool onAccount = false}) async {
    final sv = context.services;
    final inv = await runAction(
        context,
        () => sv.billing.sellProducts(_cart.values.toList(),
            memberId: _member?.id, customerName: _member == null ? tr('زائر') : null, payments: onAccount ? const [] : [PayInput(_total, _method)]));
    if (inv == null || !mounted) return;
    setState(() {
      _cart.clear();
      _member = null;
    });
    final open = await confirm(context, tr('تم البيع ✓'), message: '${inv.number} • ${fmtMoney(inv.total)}', ok: tr('عرض الفاتورة'));
    if (open && mounted) context.push(InvoiceScreen(invoiceId: inv.id));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final q = _q.text.trim().toLowerCase();
    final products = g.products.all.where((p) => p.active && (q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode == q)).toList()
      ..sort((a, b) => (a.category ?? '').compareTo(b.category ?? ''));
    final today = Range.today(g.now());
    final todaySales = g.invoices.all.where((i) => !i.voided && today.has(i.date) && i.items.any((x) => x.kind == ItemKind.product)).fold(0.0, (s, i) => s + i.total);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('المتجر')),
        actions: [
          Center(child: Pill('${tr('اليوم')}: ${fmtMoney(todaySales)}', brandSeed)),
          IconButton(tooltip: tr('المنتجات والمخزون'), icon: const Icon(Icons.inventory_2_outlined), onPressed: () => context.push(const ProductsScreen())),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.colors.surface, boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final l in _cart.values)
                    Row(children: [
                      Expanded(child: Text(l.product.name)),
                      IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => l.qty <= 1 ? _cart.remove(l.product.id) : l.qty--), icon: const Icon(Icons.remove_circle_outline)),
                      Text(fmtNum(l.qty)),
                      IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => l.qty++), icon: const Icon(Icons.add_circle_outline)),
                      SizedBox(width: 90, child: Text(fmtMoney(l.total), textAlign: TextAlign.end)),
                    ]),
                  const Divider(),
                  Row(children: [
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(_member?.name ?? tr('زائر')),
                      onPressed: () async {
                        final m = await context.push<Member>(const MembersScreen(pickOnly: true));
                        if (m != null) setState(() => _member = m);
                      },
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<PayMethod>(
                      value: _method,
                      underline: const SizedBox(),
                      items: [for (final m in PayMethod.values.where((x) => x != PayMethod.online)) DropdownMenuItem(value: m, child: Text(payMethodName(m)))],
                      onChanged: (v) => setState(() => _method = v!),
                    ),
                    const Spacer(),
                    Text(fmtMoney(_total), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (_member != null) ...[
                      Expanded(child: OutlinedButton(onPressed: () => _checkout(onAccount: true), child: Text(tr('على حساب العضو')))),
                      const SizedBox(width: 8),
                    ],
                    Expanded(flex: 2, child: FilledButton.icon(onPressed: () => _checkout(), icon: const Icon(Icons.check), label: Text(tr('دفع {a}', {'a': fmtMoney(_total)})))),
                  ]),
                ]),
              ),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SearchField(controller: _q, hint: tr('ابحث أو امسح باركود المنتج'), onChanged: (v) {
            final exact = g.products.all.where((p) => p.barcode != null && p.barcode == v.trim());
            if (exact.isNotEmpty) {
              _add(exact.first);
              _q.clear();
            }
            setState(() {});
          }),
        ),
        Expanded(
          child: products.isEmpty
              ? EmptyState(
                  icon: Icons.storefront_outlined,
                  title: tr('لا توجد منتجات'),
                  action: FilledButton.icon(onPressed: () => context.push(const ProductsScreen()), icon: const Icon(Icons.add), label: Text(tr('إضافة منتجات'))),
                )
              : GridView(
                  // الارتفاع يتبع حجم الخط (الجوالات القديمة غالباً بخط مكبّر)
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 32 + MediaQuery.textScalerOf(context).scale(118),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final p in products)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: p.trackStock && p.stock <= 0 ? null : () => _add(p),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const Spacer(),
                              Text(fmtMoney(p.price), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              if (p.trackStock)
                                Text(tr('المتوفر: {n}', {'n': fmtNum(p.stock)}),
                                    style: TextStyle(fontSize: 12, color: p.lowStock ? StatusColors.expired : context.colors.onSurfaceVariant)),
                              if (_cart[p.id] != null) Pill('× ${fmtNum(_cart[p.id]!.qty)}', brandSeed),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ]),
    );
  }
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.products.all.toList()..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text(tr('المنتجات والمخزون'))),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, null), child: const Icon(Icons.add)),
      body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
        for (final p in list)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: (p.lowStock ? StatusColors.expired : brandSeed).withValues(alpha: 0.12),
              child: Icon(Icons.inventory_2_outlined, color: p.lowStock ? StatusColors.expired : brandSeed),
            ),
            title: Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: p.active ? null : TextDecoration.lineThrough)),
            subtitle: Text([fmtMoney(p.price), if (p.cost > 0) '${tr('التكلفة')} ${fmtMoney(p.cost)}', if (p.category != null) p.category!].join(' • ')),
            trailing: p.trackStock
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(fmtNum(p.stock), style: TextStyle(fontWeight: FontWeight.w800, color: p.lowStock ? StatusColors.expired : null)),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                      onPressed: () async {
                        final v = await askText(context, tr('إضافة كمية لـ {p}', {'p': p.name}), number: true, ok: tr('إضافة'));
                        final n = parseAmount(v);
                        if (n == null) return;
                        p.stock += n;
                        await g.putAll([p, g.auditEntry('stock', '${p.name} +${fmtNum(n)}')]);
                      },
                      child: Text(tr('+ مخزون'), style: const TextStyle(fontSize: 12)),
                    ),
                  ])
                : null,
            onTap: () => _edit(context, p),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, Product? p0) async {
    final g = context.gym;
    final p = p0 != null ? Product.fromMap(p0.toMap()) : Product(id: newId(), name: '');
    final f = {
      'name': TextEditingController(text: p.name),
      'price': TextEditingController(text: p.price == 0 ? '' : fmtNum(p.price)),
      'cost': TextEditingController(text: p.cost == 0 ? '' : fmtNum(p.cost)),
      'stock': TextEditingController(text: fmtNum(p.stock)),
      'min': TextEditingController(text: fmtNum(p.minStock)),
      'cat': TextEditingController(text: p.category ?? ''),
      'barcode': TextEditingController(text: p.barcode ?? ''),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p0 == null ? tr('منتج جديد') : p.name),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: f['name'], decoration: InputDecoration(labelText: tr('الاسم'))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: f['price'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('سعر البيع')))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: f['cost'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('التكلفة')))),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('تتبّع المخزون')), value: p.trackStock, onChanged: (v) => set(() => p.trackStock = v)),
                if (p.trackStock)
                  Row(children: [
                    Expanded(child: TextField(controller: f['stock'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('الكمية')))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: f['min'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('حد التنبيه')))),
                  ]),
                const SizedBox(height: 8),
                TextField(controller: f['cat'], decoration: InputDecoration(labelText: tr('الفئة'))),
                const SizedBox(height: 8),
                TextField(controller: f['barcode'], decoration: InputDecoration(labelText: tr('الباركود'))),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('متاح للبيع')), value: p.active, onChanged: (v) => set(() => p.active = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    if (ok != true || f['name']!.text.trim().isEmpty || !context.mounted) return;
    final nums = [for (final k in ['price', 'cost', 'stock', 'min']) parseAmount(f[k]!.text) ?? 0];
    if (nums.any((x) => x < 0)) {
      context.toast(tr('السعر والتكلفة والكمية لا تكون سالبة'), error: true);
      return;
    }
    p
      ..name = f['name']!.text.trim()
      ..price = parseAmount(f['price']!.text) ?? 0
      ..cost = parseAmount(f['cost']!.text) ?? 0
      ..stock = parseAmount(f['stock']!.text) ?? 0
      ..minStock = parseAmount(f['min']!.text) ?? 0
      ..category = f['cat']!.text.trim().isEmpty ? null : f['cat']!.text.trim()
      ..barcode = f['barcode']!.text.trim().isEmpty ? null : f['barcode']!.text.trim();
    await g.put(p);
  }
}

