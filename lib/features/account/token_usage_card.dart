// The token usage card on the Students page (#183): what the tutor's calls
// to the model cost per class, over the last 7 and 30 days, split into
// input, cached input and output. Tokens, not money — the price per token
// is OpenAI's and changes.
//
// Read from the `usage` block of every student's turn records, once when
// the page opens; the class of each student comes from the live account
// list the page already polls, so a class reassigned on the page moves its
// student's tokens along at once.

import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The longest window the card shows.
const Duration kTokenUsageWindow = Duration(days: 30);

/// The short one.
const Duration kTokenUsageShortWindow = Duration(days: 7);

/// One class's row on the card.
class ClassTokenUsage {
  const ClassTokenUsage({
    required this.className,
    required this.last7Days,
    required this.last30Days,
  });

  /// Empty for the students without a class.
  final String className;
  final TokenUsage last7Days;
  final TokenUsage last30Days;
}

/// Adds [entries] up per class of the student they belong to, for the
/// 7 and the 30 days before [now].
///
/// Every class in [accounts] gets a row, one without usage too; the
/// students without a class — and records of an account that no longer
/// exists — share a last row, there only when they used anything. Classes
/// are sorted the way the class filter sorts them.
List<ClassTokenUsage> tokenUsageByClass({
  required List<Account> accounts,
  required List<TurnUsageEntry> entries,
  required DateTime now,
}) {
  final classOf = {for (final a in accounts) a.uid: a.className};
  final since30 = now.subtract(kTokenUsageWindow);
  final since7 = now.subtract(kTokenUsageShortWindow);
  final last7 = <String, TokenUsage>{};
  final last30 = <String, TokenUsage>{};
  for (final name in classOf.values) {
    if (name.isEmpty) continue;
    last7[name] = TokenUsage.zero;
    last30[name] = TokenUsage.zero;
  }
  for (final e in entries) {
    if (e.at.isBefore(since30) || e.at.isAfter(now)) continue;
    final name = classOf[e.uid] ?? '';
    last30[name] = (last30[name] ?? TokenUsage.zero) + e.tokens;
    if (!e.at.isBefore(since7)) {
      last7[name] = (last7[name] ?? TokenUsage.zero) + e.tokens;
    }
  }
  final names = last30.keys.where((n) => n.isNotEmpty).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  ClassTokenUsage row(String name) => ClassTokenUsage(
    className: name,
    last7Days: last7[name] ?? TokenUsage.zero,
    last30Days: last30[name] ?? TokenUsage.zero,
  );
  return [for (final n in names) row(n), if (last30.containsKey('')) row('')];
}

/// The card itself: a header with the 30-day total, and — opened — the
/// table per class.
class TokenUsageCard extends ConsumerStatefulWidget {
  const TokenUsageCard({super.key, required this.accounts});

  /// Every account on the page, for the class each student is in.
  final List<Account> accounts;

  @override
  ConsumerState<TokenUsageCard> createState() => _TokenUsageCardState();
}

class _TokenUsageCardState extends ConsumerState<TokenUsageCard> {
  late final DateTime _now;
  late final Future<List<TurnUsageEntry>> _entries;

  /// Closed by default: the card is a glance, the student list is what the
  /// page is for.
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now().toUtc();
    _entries = ref
        .read(turnHistoryServiceProvider)
        .listUsageSince(_now.subtract(kTokenUsageWindow));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final format = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    return FutureBuilder<List<TurnUsageEntry>>(
      future: _entries,
      builder: (context, snap) {
        final entries = snap.data;
        final rows = entries == null
            ? const <ClassTokenUsage>[]
            : tokenUsageByClass(
                accounts: widget.accounts,
                entries: entries,
                now: _now,
              );
        final total = rows.fold(
          TokenUsage.zero,
          (sum, r) => sum + r.last30Days,
        );

        final String summary;
        if (snap.hasError) {
          summary = l.accounts_usage_loadError('${snap.error}');
        } else if (entries == null) {
          summary = '…';
        } else {
          summary = l.accounts_usage_summary(
            format.format(total.promptTokens + total.completionTokens),
          );
        }

        return Material(
          key: const Key('token-usage-card'),
          color: AppColors.ink1,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppColors.ink2),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const Key('token-usage-toggle'),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.m,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.data_usage_outlined,
                        size: 18,
                        color: AppColors.fgMute,
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Text(
                        l.accounts_usage_title,
                        style: TextStyle(
                          color: AppColors.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Text(
                          summary,
                          key: const Key('token-usage-summary'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.fgMute,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.fgMute,
                      ),
                    ],
                  ),
                ),
              ),
              if (_open && entries != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.m,
                  ),
                  // Capped, so a school with many classes still leaves the
                  // student list room on a small window.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: _UsageTable(
                        rows: rows,
                        empty: total.isZero,
                        format: format,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UsageTable extends StatelessWidget {
  const _UsageTable({
    required this.rows,
    required this.empty,
    required this.format,
  });

  final List<ClassTokenUsage> rows;
  final bool empty;
  final NumberFormat format;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final note = TextStyle(color: AppColors.fgFaint, fontSize: 12, height: 1.4);
    if (empty) {
      return Text(
        l.accounts_usage_empty,
        key: const Key('token-usage-empty'),
        style: note,
      );
    }
    final head = TextStyle(
      color: AppColors.fgFaint,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

    Widget number(int n) => Expanded(
      child: Text(
        format.format(n),
        textAlign: TextAlign.right,
        style: AppMono.tnum(size: 13, weight: FontWeight.w500),
      ),
    );
    Widget label(String text, {int flex = 1, TextAlign? align}) => Expanded(
      flex: flex,
      child: Text(text, textAlign: align ?? TextAlign.right, style: head),
    );
    List<Widget> split(TokenUsage u) => [
      number(u.uncachedPromptTokens),
      number(u.cachedTokens),
      number(u.completionTokens),
    ];
    List<Widget> splitHead() => [
      label(l.accounts_usage_input),
      label(l.accounts_usage_cached),
      label(l.accounts_usage_output),
    ];
    const gap = SizedBox(width: AppSpacing.xl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.accounts_usage_subtitle, style: note),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            label('', flex: 2),
            gap,
            label(l.accounts_usage_last7, flex: 3, align: TextAlign.center),
            gap,
            label(l.accounts_usage_last30, flex: 3, align: TextAlign.center),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          children: [
            label(l.accounts_usage_class, flex: 2, align: TextAlign.left),
            gap,
            ...splitHead(),
            gap,
            ...splitHead(),
          ],
        ),
        Divider(height: AppSpacing.m, color: AppColors.ink2),
        for (final r in rows)
          Padding(
            key: Key('token-usage-row-${r.className}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    r.className.isEmpty
                        ? l.accounts_classFilter_none
                        : r.className,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: r.className.isEmpty
                          ? AppColors.fgMute
                          : AppColors.fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                gap,
                ...split(r.last7Days),
                gap,
                ...split(r.last30Days),
              ],
            ),
          ),
      ],
    );
  }
}
