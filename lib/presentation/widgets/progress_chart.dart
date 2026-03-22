import 'package:fl_chart/fl_chart.dart';
import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Line chart for strength progress (load over time), with optional ratio line.
class StrengthProgressChart extends StatelessWidget {
  const StrengthProgressChart({
    super.key,
    required this.points,
    required this.unit,
    this.showRatio = false,
  });

  final List<StrengthPoint> points;

  /// Display unit: 'kg' or 'lbs'. Values are converted from stored kg before rendering.
  final String unit;

  /// When true, renders a second line for loadKg / bodyWeightKg ratio
  /// on sessions where bodyWeightKg is available.
  final bool showRatio;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _EmptyState(message: 'No data logged yet');
    }

    final displayPoints = points.map((p) {
      final displayLoad = unit == 'lbs' ? p.loadKg * 2.20462 : p.loadKg;
      return (
        date: p.date,
        loadDisplay: displayLoad,
        ratio: (p.bodyWeightKg != null && p.bodyWeightKg! > 0)
            ? p.loadKg / p.bodyWeightKg!
            : null,
      );
    }).toList();

    final minX = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final allLoads = displayPoints.map((p) => p.loadDisplay);
    final minY = (allLoads.reduce((a, b) => a < b ? a : b) * 0.9);
    final maxY = (allLoads.reduce((a, b) => a > b ? a : b) * 1.1);

    final loadSpots = displayPoints
        .map(
          (p) => FlSpot(
            p.date.millisecondsSinceEpoch.toDouble(),
            double.parse(p.loadDisplay.toStringAsFixed(1)),
          ),
        )
        .toList();

    final ratioSpots = showRatio
        ? displayPoints
              .where((p) => p.ratio != null)
              .map(
                (p) => FlSpot(
                  p.date.millisecondsSinceEpoch.toDouble(),
                  double.parse(p.ratio!.toStringAsFixed(2)),
                ),
              )
              .toList()
        : <FlSpot>[];

    final lineBarsData = [
      LineChartBarData(
        spots: loadSpots,
        isCurved: true,
        color: context.colorScheme.primary,
        barWidth: 2.5,
        dotData: FlDotData(show: points.length <= 12),
        belowBarData: BarAreaData(
          show: true,
          color: context.colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      if (showRatio && ratioSpots.isNotEmpty)
        LineChartBarData(
          spots: ratioSpots,
          isCurved: true,
          color: context.colorScheme.tertiary,
          barWidth: 2,
          dashArray: [6, 3],
          dotData: FlDotData(show: false),
        ),
    ];

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: lineBarsData,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: context.bodyMedium,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _xInterval(minX, maxX),
                getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    value.toInt(),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM yy').format(date),
                      style: context.bodyMedium,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.colorScheme.outline.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(
                  spot.x.toInt(),
                );
                final isRatio = spot.barIndex == 1;
                final label = isRatio
                    ? '${spot.y.toStringAsFixed(2)}×BW'
                    : '${spot.y.toStringAsFixed(1)} $unit';
                return LineTooltipItem(
                  '${DateFormat('d MMM yy').format(date)}\n$label',
                  context.bodyMedium,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    // Show ~4 labels
    return (rangeMs / 4).ceilToDouble();
  }
}

/// Line chart for grade progress with two lines: max grade climbed and flashed.
/// Both datasets share one chart and y-axis. Either line is omitted when empty.
/// Tooltip shows the stored grade string (honoring each entry's own grade system).
class GradeProgressChart extends StatelessWidget {
  const GradeProgressChart({
    super.key,
    required this.climbed,
    required this.flashed,
  });

  final List<GradePoint> climbed;
  final List<GradePoint> flashed;

  @override
  Widget build(BuildContext context) {
    if (climbed.isEmpty && flashed.isEmpty) {
      return _EmptyState(message: 'No grades logged yet');
    }

    // Build a lookup from gradeIndex → display label using the stored system.
    // If two entries share an index but have different systems, last write wins —
    // acceptable edge case; the tooltip always shows the correct per-entry label.
    final indexToLabel = <int, String>{};
    for (final p in [...climbed, ...flashed]) {
      indexToLabel[p.grade.gradeIndex] = gradeLabel(p.grade);
    }

    final allPoints = [...climbed, ...flashed];
    final allDates = allPoints.map((p) => p.date.millisecondsSinceEpoch.toDouble());
    final allIndices = allPoints.map((p) => p.grade.gradeIndex.toDouble()).toList();
    final minX = allDates.reduce((a, b) => a < b ? a : b);
    final maxX = allDates.reduce((a, b) => a > b ? a : b);
    final minY = (allIndices.reduce((a, b) => a < b ? a : b) - 1).clamp(0, double.infinity).toDouble();
    final maxY = allIndices.reduce((a, b) => a > b ? a : b) + 1;

    FlSpot toSpot(GradePoint p) => FlSpot(
          p.date.millisecondsSinceEpoch.toDouble(),
          p.grade.gradeIndex.toDouble(),
        );

    final lineBarsData = [
      if (climbed.isNotEmpty)
        LineChartBarData(
          spots: climbed.map(toSpot).toList(),
          isCurved: true,
          color: context.colorScheme.primary,
          barWidth: 2.5,
          dotData: FlDotData(show: climbed.length <= 12),
          belowBarData: BarAreaData(
            show: true,
            color: context.colorScheme.primary.withValues(alpha: 0.08),
          ),
        ),
      if (flashed.isNotEmpty)
        LineChartBarData(
          spots: flashed.map(toSpot).toList(),
          isCurved: true,
          color: context.colorScheme.secondary,
          barWidth: 2,
          dashArray: [6, 3],
          dotData: FlDotData(show: flashed.length <= 12),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Row(
          children: [
            if (climbed.isNotEmpty) ...[
              _LegendDot(color: context.colorScheme.primary),
              const SizedBox(width: 4),
              Text('Climbed', style: context.bodyMedium),
              const SizedBox(width: 16),
            ],
            if (flashed.isNotEmpty) ...[
              _LegendDot(color: context.colorScheme.secondary),
              const SizedBox(width: 4),
              Text('Flashed', style: context.bodyMedium),
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              lineBarsData: lineBarsData,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (value, meta) {
                      final label = indexToLabel[value.round()];
                      if (label == null) return const SizedBox.shrink();
                      return Text(label, style: context.bodyMedium);
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _xInterval(minX, maxX),
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          DateFormat('MMM yy').format(date),
                          style: context.bodyMedium,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: context.colorScheme.outline.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                    final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                    final label = indexToLabel[spot.y.round()] ?? '?';
                    // barIndex 0 = climbed (when present), 1 = flashed
                    final metric = (climbed.isNotEmpty && spot.barIndex == 0)
                        ? 'Climbed'
                        : 'Flashed';
                    return LineTooltipItem(
                      '${DateFormat('d MMM yy').format(date)}\n$label ($metric)',
                      context.bodyMedium,
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    return (rangeMs / 4).ceilToDouble();
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Line chart for body weight over time, displayed in user's preferred unit.
class BodyWeightChart extends StatelessWidget {
  const BodyWeightChart({
    super.key,
    required this.points,
    required this.unit,
  });

  final List<({DateTime date, double bodyWeightKg})> points;

  /// Display unit: 'kg' or 'lbs'. Values are converted from stored kg before rendering.
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _EmptyState(message: 'No body weight logged yet');
    }

    final displayPoints = points.map((p) {
      final displayWeight = unit == 'lbs' ? p.bodyWeightKg * 2.20462 : p.bodyWeightKg;
      return (date: p.date, weight: displayWeight);
    }).toList();

    final minX = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final allWeights = displayPoints.map((p) => p.weight);
    final minY = allWeights.reduce((a, b) => a < b ? a : b) * 0.9;
    final maxY = allWeights.reduce((a, b) => a > b ? a : b) * 1.1;

    final spots = displayPoints
        .map((p) => FlSpot(
              p.date.millisecondsSinceEpoch.toDouble(),
              double.parse(p.weight.toStringAsFixed(1)),
            ))
        .toList();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: context.colorScheme.tertiary,
              barWidth: 2.5,
              dotData: FlDotData(show: points.length <= 12),
              belowBarData: BarAreaData(
                show: true,
                color: context.colorScheme.tertiary.withValues(alpha: 0.08),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: context.bodyMedium,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _xInterval(minX, maxX),
                getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM yy').format(date),
                      style: context.bodyMedium,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.colorScheme.outline.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                  '${DateFormat('d MMM yy').format(date)}\n${spot.y.toStringAsFixed(1)} $unit',
                  context.bodyMedium,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    return (rangeMs / 4).ceilToDouble();
  }
}

/// Simple empty-state placeholder used when there are no data points.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 40,
              color: context.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(message, style: context.bodyMedium),
          ],
        ),
      ),
    );
  }
}
