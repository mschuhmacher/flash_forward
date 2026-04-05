import 'dart:math' show pi;

import 'package:fl_chart/fl_chart.dart';
import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── X-axis scale helpers ──────────────────────────────────────────────────────

enum _XScale { daily, weekly, monthly, quarterly, yearly }

enum StrengthDisplayMode { load, ratio }

/// Selects the tick scale from the chart's total time range in milliseconds.
/// Scale is computed from the ORIGINAL rangeMs before any single-point padding.
_XScale _xScaleFor(double rangeMs) {
  const day = 86400000.0;
  if (rangeMs <= 6 * day) return _XScale.daily;
  if (rangeMs <= 42 * day) return _XScale.weekly;
  if (rangeMs <= 274 * day) return _XScale.monthly;
  if (rangeMs <= 730 * day) return _XScale.quarterly;
  return _XScale.yearly;
}

/// Returns true when [utcDate] is a tick position for [scale].
bool _isTickDate(DateTime utcDate, _XScale scale) => switch (scale) {
  _XScale.daily => true,
  _XScale.weekly => utcDate.weekday == DateTime.monday,
  _XScale.monthly => utcDate.day == 1,
  _XScale.quarterly =>
    utcDate.day == 1 && [1, 4, 7, 10].contains(utcDate.month),
  _XScale.yearly => utcDate.day == 1 && utcDate.month == 1,
};

/// Returns the label string for a tick date.
/// On monthly and quarterly scales, January shows the 4-digit year number
/// instead of "Jan" so the year boundary is unambiguous.
String _tickLabel(DateTime utcDate, _XScale scale) {
  if (utcDate.month == 1 &&
      (scale == _XScale.monthly || scale == _XScale.quarterly)) {
    return utcDate.year.toString();
  }
  return switch (scale) {
    _XScale.daily => DateFormat('d MMM').format(utcDate),
    _XScale.weekly => DateFormat('d MMM').format(utcDate),
    _XScale.monthly => DateFormat('MMM').format(utcDate),
    _XScale.quarterly => DateFormat('MMM').format(utcDate),
    _XScale.yearly => utcDate.year.toString(),
  };
}

/// Bottom-axis label widget for a given x-value (milliseconds since epoch).
/// Returns [SizedBox.shrink] for non-tick positions.
/// Labels are rotated 55° counter-clockwise ("8 to 2 on a clock face").
Widget _buildXLabel(double xMs, _XScale scale, BuildContext context) {
  final utcDate = DateTime.fromMillisecondsSinceEpoch(xMs.toInt(), isUtc: true);
  if (!_isTickDate(utcDate, scale)) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Transform.rotate(
      angle: -pi * 55 / 180,
      child: Text(_tickLabel(utcDate, scale), style: context.bodyMedium),
    ),
  );
}

/// Integer key for a UTC date (yyyymmdd) used to match tick positions to data.
int _dayKey(DateTime utcDate) =>
    utcDate.year * 10000 + utcDate.month * 100 + utcDate.day;

/// Returns a getTitlesWidget callback that shows labels at actual data-point
/// dates when there are few points (≤ 7), and falls back to calendar-aligned
/// ticks otherwise. Keeps both charts consistent for any data density.
Widget Function(double, TitleMeta) _dataAwareXLabelBuilder({
  required Set<int> dataPointDayKeys,
  required int pointCount,
  required _XScale scale,
  required BuildContext context,
}) {
  return (double value, TitleMeta meta) {
    if (value == meta.min || value == meta.max) {
      return const SizedBox.shrink();
    }
    if (pointCount <= 7) {
      final utcDate =
          DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
      if (!dataPointDayKeys.contains(_dayKey(utcDate))) {
        return const SizedBox.shrink();
      }
      // Always use "d MMM" format for sparse data so every dot is labeled.
      return _buildXLabel(value, _XScale.daily, context);
    }
    return _buildXLabel(value, scale, context);
  };
}

/// Returns a y-axis tick interval for ratio charts (loadKg / bodyWeightKg)
/// that targets ~4 visible ticks for typical ratio ranges (0.0–2.0).
double _niceRatioInterval(double maxY) {
  if (maxY <= 0.5) return 0.1;
  if (maxY <= 1.2) return 0.2;
  if (maxY <= 2.5) return 0.5;
  return 1.0;
}

/// Line chart for strength progress (load over time), with optional ratio line.
class StrengthProgressChart extends StatelessWidget {
  const StrengthProgressChart({
    super.key,
    required this.points,
    required this.unit,
    this.displayMode = StrengthDisplayMode.load,
  });

  final List<StrengthPoint> points;

  /// Display unit: 'kg' or 'lbs'. Values are converted from stored kg before rendering.
  final String unit;

  /// Whether to show the raw load line or the load/body-weight ratio line.
  final StrengthDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _EmptyState(message: 'No data logged yet');
    }

    final displayPoints =
        points.map((p) {
          final displayLoad = unit == 'lbs' ? p.loadKg * 2.20462 : p.loadKg;
          return (
            date: p.date,
            loadDisplay: displayLoad,
            ratio:
                (p.bodyWeightKg != null && p.bodyWeightKg! > 0)
                    ? p.loadKg / p.bodyWeightKg!
                    : null,
          );
        }).toList();

    // For ratio mode, only points that have body weight are usable.
    final ratioPoints =
        displayMode == StrengthDisplayMode.ratio
            ? displayPoints.where((p) => p.ratio != null).toList()
            : <({DateTime date, double loadDisplay, double? ratio})>[];

    if (displayMode == StrengthDisplayMode.ratio && ratioPoints.isEmpty) {
      return _EmptyState(message: 'No body weight data logged yet');
    }

    var minX = points.first.date.millisecondsSinceEpoch.toDouble();
    var maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    } else {
      // 4% of range ≈ 8–9 pt inset on each side on a typical phone chart width
      // (~220 pt usable), keeping the first and last data points off the edges.
      minX -= rangeMs * 0.04;
      maxX += rangeMs * 0.04;
    }

    // Y-axis bounds scaled to the active mode's data range.
    final double minY;
    final double maxY;
    if (displayMode == StrengthDisplayMode.load) {
      final loads = displayPoints.map((p) => p.loadDisplay);
      minY = loads.reduce((a, b) => a < b ? a : b) * 0.9;
      maxY = loads.reduce((a, b) => a > b ? a : b) * 1.1;
    } else {
      final ratios = ratioPoints.map((p) => p.ratio!);
      minY = 0;
      maxY = ratios.reduce((a, b) => a > b ? a : b) * 1.1;
    }

    final double? yInterval =
        displayMode == StrengthDisplayMode.ratio
            ? _niceRatioInterval(maxY)
            : null; // null = fl_chart auto-interval (works well for load)

    final spots =
        displayMode == StrengthDisplayMode.load
            ? displayPoints
                .map(
                  (p) => FlSpot(
                    p.date.millisecondsSinceEpoch.toDouble(),
                    double.parse(p.loadDisplay.toStringAsFixed(1)),
                  ),
                )
                .toList()
            : ratioPoints
                .map(
                  (p) => FlSpot(
                    p.date.millisecondsSinceEpoch.toDouble(),
                    double.parse(p.ratio!.toStringAsFixed(2)),
                  ),
                )
                .toList();

    final lineColor =
        displayMode == StrengthDisplayMode.load
            ? context.colorScheme.primary
            : context.colorScheme.secondary;

    final dataPointDayKeys =
        points.map((p) => _dayKey(p.date.toUtc())).toSet();

    final lineBarsData = [
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: lineColor,
        barWidth: 2.5,
        dotData: FlDotData(show: points.length <= 12),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withValues(alpha: 0.08),
        ),
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
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toStringAsFixed(1),
                    style: context.bodyMedium,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: 86400000,
                getTitlesWidget: _dataAwareXLabelBuilder(
                  dataPointDayKeys: dataPointDayKeys,
                  pointCount: points.length,
                  scale: scale,
                  context: context,
                ),
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
            horizontalInterval: yInterval,
            getDrawingHorizontalLine:
                (value) => FlLine(
                  color: context.colorScheme.outline.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems:
                  (spots) =>
                      spots.map((spot) {
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          spot.x.toInt(),
                        );
                        final label =
                            displayMode == StrengthDisplayMode.ratio
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
}

/// Line chart for grade progress with two lines: max grade climbed and flashed.
/// Both datasets share one chart and y-axis. Either line is omitted when empty.
/// Tooltip shows the stored grade string (honoring each entry's own grade system).
class GradeProgressChart extends StatelessWidget {
  const GradeProgressChart({
    super.key,
    required this.climbed,
    required this.flashed,
    required this.gradeSystem,
  });

  final List<GradePoint> climbed;
  final List<GradePoint> flashed;
  final GradeSystem gradeSystem;

  @override
  Widget build(BuildContext context) {
    // Filter to only points stored in the active grade system so Font and
    // V indices are never mixed on the same axis.
    final filteredClimbed =
        climbed.where((p) => p.grade.system == gradeSystem).toList();
    final filteredFlashed =
        flashed.where((p) => p.grade.system == gradeSystem).toList();

    if (filteredClimbed.isEmpty && filteredFlashed.isEmpty) {
      return _EmptyState(message: 'No grades logged yet');
    }

    // Full ordered label list for the active system.
    final scaleLabels =
        gradeSystem == GradeSystem.fontainebleau
            ? kFontScale // indices 0-21
            : List.generate(18, (i) => 'V$i'); // V0-V17

    final allPoints = [...filteredClimbed, ...filteredFlashed];
    final allDates = allPoints.map(
      (p) => p.date.millisecondsSinceEpoch.toDouble(),
    );
    final minIdx = allPoints
        .map((p) => p.grade.gradeIndex)
        .reduce((a, b) => a < b ? a : b);
    final maxIdx = allPoints
        .map((p) => p.grade.gradeIndex)
        .reduce((a, b) => a > b ? a : b);

    // Build indexToLabel for every grade in [minIdx, maxIdx] so every y
    // position in the visible range has a label and spacing is uniform,
    // regardless of which specific grades were actually logged.
    final indexToLabel = <int, String>{
      for (int i = minIdx; i <= maxIdx; i++)
        if (i >= 0 && i < scaleLabels.length) i: scaleLabels[i],
    };

    var minX = allDates.reduce((a, b) => a < b ? a : b);
    var maxX = allDates.reduce((a, b) => a > b ? a : b);
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    } else {
      // 4% of range ≈ 8–9 pt inset on each side on a typical phone chart width
      // (~220 pt usable), keeping the first and last data points off the edges.
      minX -= rangeMs * 0.04;
      maxX += rangeMs * 0.04;
    }
    final minY = (minIdx - 1).clamp(0, scaleLabels.length - 1).toDouble();
    final maxY = (maxIdx + 1).clamp(0, scaleLabels.length - 1).toDouble();

    final dataPointDayKeys =
        allPoints.map((p) => _dayKey(p.date.toUtc())).toSet();

    FlSpot toSpot(GradePoint p) => FlSpot(
      p.date.millisecondsSinceEpoch.toDouble(),
      p.grade.gradeIndex.toDouble(),
    );

    final lineBarsData = [
      if (filteredClimbed.isNotEmpty)
        LineChartBarData(
          spots: filteredClimbed.map(toSpot).toList(),
          isCurved: true,
          curveSmoothness: 0.2,
          // preventCurveOverShooting: true,
          color: context.colorScheme.primary,
          barWidth: 2.5,
          dotData: FlDotData(show: filteredClimbed.length <= 12),
          belowBarData: BarAreaData(
            show: true,
            color: context.colorScheme.primary.withValues(alpha: 0.08),
          ),
        ),
      if (filteredFlashed.isNotEmpty)
        LineChartBarData(
          spots: filteredFlashed.map(toSpot).toList(),
          isCurved: true,
          curveSmoothness: 0.2,
          // preventCurveOverShooting: true,
          color: context.colorScheme.secondary,
          barWidth: 2,
          dashArray: [6, 3],
          dotData: FlDotData(show: filteredFlashed.length <= 12),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Row(
          children: [
            if (filteredClimbed.isNotEmpty) ...[
              _LegendDot(color: context.colorScheme.primary),
              const SizedBox(width: 4),
              Text('Climbed', style: context.bodyMedium),
              const SizedBox(width: 16),
            ],
            if (filteredFlashed.isNotEmpty) ...[
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
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) {
                        return const SizedBox.shrink();
                      }
                      final label = indexToLabel[value.round()];
                      if (label == null) return const SizedBox.shrink();
                      return Text(label, style: context.bodyMedium);
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    interval: 86400000,
                    getTitlesWidget: _dataAwareXLabelBuilder(
                      dataPointDayKeys: dataPointDayKeys,
                      pointCount: allPoints.length,
                      scale: scale,
                      context: context,
                    ),
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
                checkToShowHorizontalLine:
                    (value) => indexToLabel.containsKey(value.round()),
                getDrawingHorizontalLine:
                    (value) => FlLine(
                      color: context.colorScheme.outline.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems:
                      (touchedSpots) =>
                          touchedSpots.map((spot) {
                            final date = DateTime.fromMillisecondsSinceEpoch(
                              spot.x.toInt(),
                            );
                            final label = indexToLabel[spot.y.round()] ?? '?';
                            // barIndex 0 = climbed (when present), 1 = flashed
                            final metric =
                                (climbed.isNotEmpty && spot.barIndex == 0)
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
  const BodyWeightChart({super.key, required this.points, required this.unit});

  final List<({DateTime date, double bodyWeightKg})> points;

  /// Display unit: 'kg' or 'lbs'. Values are converted from stored kg before rendering.
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _EmptyState(message: 'No body weight logged yet');
    }

    final displayPoints =
        points.map((p) {
          final displayWeight =
              unit == 'lbs' ? p.bodyWeightKg * 2.20462 : p.bodyWeightKg;
          return (date: p.date, weight: displayWeight);
        }).toList();

    var minX = points.first.date.millisecondsSinceEpoch.toDouble();
    var maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    } else {
      // 4% of range ≈ 8–9 pt inset on each side on a typical phone chart width
      // (~220 pt usable), keeping the first and last data points off the edges.
      minX -= rangeMs * 0.04;
      maxX += rangeMs * 0.04;
    }
    final allWeights = displayPoints.map((p) => p.weight);
    final minY = allWeights.reduce((a, b) => a < b ? a : b) * 0.9;
    final maxY = allWeights.reduce((a, b) => a > b ? a : b) * 1.1;

    final dataPointDayKeys =
        points.map((p) => _dayKey(p.date.toUtc())).toSet();

    final spots =
        displayPoints
            .map(
              (p) => FlSpot(
                p.date.millisecondsSinceEpoch.toDouble(),
                double.parse(p.weight.toStringAsFixed(1)),
              ),
            )
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
              curveSmoothness: 0.2,
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
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toStringAsFixed(1),
                    style: context.bodyMedium,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: 86400000,
                getTitlesWidget: _dataAwareXLabelBuilder(
                  dataPointDayKeys: dataPointDayKeys,
                  pointCount: points.length,
                  scale: scale,
                  context: context,
                ),
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
            getDrawingHorizontalLine:
                (value) => FlLine(
                  color: context.colorScheme.outline.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems:
                  (spots) =>
                      spots.map((spot) {
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          spot.x.toInt(),
                        );
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
