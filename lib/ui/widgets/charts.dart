import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'common.dart';

/// عمود واحد لكل قيمة (سلسلة واحدة بلون العلامة)، مع تلميح عند اللمس وشبكة خفيفة
class SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels; // تسمية المحور (قد تكون فارغة لبعض الأعمدة)
  final String Function(double) format;
  final List<String>? tooltipTitles;
  final double height;
  final Color? color;

  const SimpleBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.format,
    this.tooltipTitles,
    this.height = 180,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    final maxV = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final barW = values.length > 20 ? 6.0 : (values.length > 10 ? 10.0 : 16.0);
    final muted = context.colors.onSurfaceVariant;
    return SizedBox(
      height: height,
      child: Directionality(
        // الزمن يتقدم من اليسار لليمين حتى في الواجهة العربية (كما في الرسوم المالية)
        textDirection: TextDirection.ltr,
        child: BarChart(
          BarChartData(
            maxY: maxV <= 0 ? 1 : maxV * 1.15,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxV <= 0 ? 1 : maxV / 3,
              getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length || labels[i].isEmpty) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[i], style: TextStyle(fontSize: 10, color: muted)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => context.colors.inverseSurface,
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${tooltipTitles?[group.x] ?? labels[group.x]}\n${format(rod.toY)}',
                  TextStyle(color: context.colors.onInverseSurface, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: c,
                    width: barW,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط أفقي للمقارنة داخل القوائم (توزيع طرق الدفع، أشهر الباقات...)
class ShareBar extends StatelessWidget {
  final String label;
  final String value;
  final double fraction;
  final Color? color;
  const ShareBar({super.key, required this.label, required this.value, required this.fraction, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 8,
              color: color ?? context.colors.primary,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
        ]),
      );
}
