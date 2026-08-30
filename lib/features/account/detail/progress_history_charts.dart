import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Duration _kHistoryWindow = Duration(days: 30);

/// Renders one `LineChart` per root goal that has any history in the last 30 days.
class ProgressHistoryCharts extends ConsumerWidget {
  const ProgressHistoryCharts({
    super.key,
    required this.uid,
    required this.goals,
  });

  final String uid;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return StreamBuilder<List<ProgressSample>>(
      stream: ref
          .read(progressServiceProvider)
          .watchHistoryForUser(
            uid,
            since: DateTime.now().toUtc().subtract(_kHistoryWindow),
          ),
      builder: (context, snap) {
        if (snap.hasError) {
          return _frame(
            theme,
            l,
            child: Text(
              l.drawer_history_loadError,
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        if (!snap.hasData) {
          return _frame(
            theme,
            l,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        }
        final samples = snap.data!;
        final roots = goals.where((g) => g.parentId == null).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        final childrenByParent = <String, List<Goal>>{};
        for (final g in goals.where((g) => g.parentId != null)) {
          childrenByParent.putIfAbsent(g.parentId!, () => []).add(g);
        }
        final samplesByGoal = <String, List<ProgressSample>>{};
        for (final s in samples) {
          samplesByGoal.putIfAbsent(s.goalID, () => []).add(s);
        }

        final roots2 = roots.where((root) {
          final children = childrenByParent[root.id] ?? const <Goal>[];
          return children.any(
            (c) => (samplesByGoal[c.id] ?? const <ProgressSample>[]).isNotEmpty,
          );
        }).toList();

        if (roots2.isEmpty) {
          return _frame(
            theme,
            l,
            child: Text(
              l.drawer_history_empty,
              style: theme.textTheme.bodySmall,
            ),
          );
        }

        return _frame(
          theme,
          l,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roots2.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final root = roots2[index];
              final children = childrenByParent[root.id] ?? const <Goal>[];
              return _RootGoalChart(
                root: root,
                children: children,
                samplesByGoal: samplesByGoal,
              );
            },
          ),
        );
      },
    );
  }

  Widget _frame(ThemeData theme, AppLocalizations l, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.drawer_history_title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _RootGoalChart extends StatelessWidget {
  const _RootGoalChart({
    required this.root,
    required this.children,
    required this.samplesByGoal,
  });

  final Goal root;
  final List<Goal> children;
  final Map<String, List<ProgressSample>> samplesByGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final activeChildren = children
        .where(
          (c) => (samplesByGoal[c.id] ?? const <ProgressSample>[]).isNotEmpty,
        )
        .toList();

    if (activeChildren.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(root.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                l.drawer_history_card_empty,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final palette = _palette(theme);
    final now = DateTime.now().toUtc();
    final start = now.subtract(_kHistoryWindow);

    final lines = <LineChartBarData>[];
    final perChild = <_ChildSeries>[];

    for (var i = 0; i < activeChildren.length; i++) {
      final child = activeChildren[i];
      final samples = samplesByGoal[child.id] ?? const <ProgressSample>[];
      final spots = _toSpots(samples, start);
      if (spots.isEmpty) continue;
      final color = palette[i % palette.length];
      perChild.add(_ChildSeries(child: child, spots: spots, color: color));
      lines.add(
        LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 1.5,
          isCurved: false,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final rootSpots = _rootAverage(perChild);
    if (rootSpots.isNotEmpty) {
      lines.add(
        LineChartBarData(
          spots: rootSpots,
          color: theme.colorScheme.onSurfaceVariant,
          barWidth: 3,
          isCurved: false,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final maxX = now.difference(start).inHours.toDouble();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(root.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: 0,
                  maxY: 1.0,
                  lineBarsData: lines,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 0.25,
                        getTitlesWidget: (value, _) => Text(
                          value.toStringAsFixed(2),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: maxX <= 0 ? 1 : maxX / 4,
                        getTitlesWidget: (value, _) {
                          final ts = start.add(Duration(hours: value.round()));
                          return Text(
                            '${ts.month}/${ts.day}',
                            style: theme.textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final s in perChild)
                  _LegendDot(color: s.color, label: s.child.title),
                _LegendDot(
                  color: theme.colorScheme.onSurfaceVariant,
                  label: l.drawer_history_legend_average,
                  thick: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _toSpots(List<ProgressSample> samples, DateTime start) {
    final spots = <FlSpot>[];
    for (final s in samples) {
      final dt = s.at.toUtc();
      if (dt.isBefore(start)) continue;
      final x = dt.difference(start).inHours.toDouble();
      spots.add(FlSpot(x, s.progress.clamp(0.0, 1.0)));
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  List<FlSpot> _rootAverage(List<_ChildSeries> series) {
    if (series.isEmpty) return const [];
    final xs = <double>{};
    for (final s in series) {
      for (final spot in s.spots) {
        xs.add(spot.x);
      }
    }
    final sortedXs = xs.toList()..sort();
    final out = <FlSpot>[];
    final lastByChild = <int, double>{};
    for (final x in sortedXs) {
      for (var i = 0; i < series.length; i++) {
        for (final spot in series[i].spots) {
          if (spot.x == x) lastByChild[i] = spot.y;
        }
      }
      if (lastByChild.length < series.length) continue;
      double total = 0;
      for (final v in lastByChild.values) {
        total += v;
      }
      out.add(FlSpot(x, total / lastByChild.length));
    }
    return out;
  }

  List<Color> _palette(ThemeData theme) => [
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    Colors.orange.shade400,
    Colors.purple.shade400,
    Colors.teal.shade400,
    Colors.brown.shade400,
    Colors.pink.shade400,
  ];
}

class _ChildSeries {
  _ChildSeries({required this.child, required this.spots, required this.color});

  final Goal child;
  final List<FlSpot> spots;
  final Color color;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.thick = false,
  });

  final Color color;
  final String label;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: thick ? 18 : 12, height: thick ? 4 : 2, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
