import '../core/money.dart';
import 'base.dart';

/// منتج في متجر النادي (مكملات، مشروبات، ملابس) أو خدمة بلا مخزون (خزانة، منشفة)
class Product implements Entity {
  @override
  final String id;
  String name;
  String? category;
  String? sku;
  String? barcode;
  double price;
  double cost; // متوسط تكلفة الوحدة (يُحدّث مع كل شراء)
  bool trackStock;
  double stock;
  double minStock; // تنبيه إعادة الطلب عند الوصول لهذا الحد
  String unit;
  String? photo;
  bool active;

  Product({
    required this.id,
    required this.name,
    this.category,
    this.sku,
    this.barcode,
    this.price = 0,
    this.cost = 0,
    this.trackStock = true,
    this.stock = 0,
    this.minStock = 0,
    this.unit = 'قطعة',
    this.photo,
    this.active = true,
  });

  bool get lowStock => trackStock && stock <= minStock;

  double get margin => roundMoney(price - cost);

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'category': category,
        'sku': sku,
        'barcode': barcode,
        'price': price,
        'cost': cost == 0 ? null : cost,
        'trackStock': trackStock,
        'stock': stock,
        'minStock': minStock == 0 ? null : minStock,
        'unit': unit,
        'photo': photo,
        'active': active,
      });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: asStr(m['id']),
        name: asStr(m['name']),
        category: asStrOrNull(m['category']),
        sku: asStrOrNull(m['sku']),
        barcode: asStrOrNull(m['barcode']),
        price: asDouble(m['price']),
        cost: asDouble(m['cost']),
        trackStock: asBool(m['trackStock'], true),
        stock: asDouble(m['stock']),
        minStock: asDouble(m['minStock']),
        unit: asStr(m['unit'], 'قطعة'),
        photo: asStrOrNull(m['photo']),
        active: asBool(m['active'], true),
      );
}

/// حركة مخزون: الكمية موجبة للإضافة وسالبة للخصم
enum StockKind { purchase, sale, saleReturn, adjust, waste }

StockKind stockKindFrom(Object? v) =>
    StockKind.values.firstWhere((k) => k.name == v, orElse: () => StockKind.adjust);

class StockMove implements Entity {
  @override
  final String id;
  final String productId;
  final DateTime time;
  final StockKind kind;
  final double qty;
  final double unitCost;
  final String? invoiceId; // لحركات البيع والمرتجع
  final String? supplier;
  final String? note;
  final String? by;

  StockMove({
    required this.id,
    required this.productId,
    required this.time,
    required this.kind,
    required this.qty,
    this.unitCost = 0,
    this.invoiceId,
    this.supplier,
    this.note,
    this.by,
  });

  double get value => roundMoney(qty * unitCost);

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'productId': productId,
        'time': time.toIso8601String(),
        'kind': kind.name,
        'qty': qty,
        'unitCost': unitCost == 0 ? null : unitCost,
        'invoiceId': invoiceId,
        'supplier': supplier,
        'note': note,
        'by': by,
      });

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: asStr(m['id']),
        productId: asStr(m['productId']),
        time: asTime(m['time']) ?? DateTime.now(),
        kind: stockKindFrom(m['kind']),
        qty: asDouble(m['qty']),
        unitCost: asDouble(m['unitCost']),
        invoiceId: asStrOrNull(m['invoiceId']),
        supplier: asStrOrNull(m['supplier']),
        note: asStrOrNull(m['note']),
        by: asStrOrNull(m['by']),
      );
}

/// متوسط التكلفة المرجّح بعد شراء [qty] بسعر [unitCost]
double weightedCost(double oldStock, double oldCost, double qty, double unitCost) {
  final total = oldStock + qty;
  if (oldStock <= 0 || total <= 0) return unitCost;
  return roundMoney((oldStock * oldCost + qty * unitCost) / total);
}
