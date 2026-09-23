// The student's own "Mijn rapporten" tab (#151): the frozen reports #150
// released, read by the student they belong to.
//
// Reads one query — the signed-in user's own `/uid` partition of the
// `reports` container, which is the query that container was partitioned for.
// Nothing unreleased exists there at all (an unpublished milestone has no
// docs), so there is no "may this student see it?" rule to get wrong here,
// and no grade proposal is ever touched: a student reads the published copy
// or nothing.
//
// The order on the page *is* the issue. PUNTENFORMULE invites every student
// to recompute their own number, so the arithmetic has to be here — but the
// grade and the reasoning come first and the breakdown stays folded away.
// A student who wants to check the sum opens it; a student reading their
// report meets a number and a sentence, not a formula.
//
// What the breakdown can show is exactly what the published doc carries:
// M_start → M_eind, G, k / u / d, the core and extension counts, and the
// level the core had to be demonstrated at. The two teacher-side numbers
// behind d ("demonstrated at hard: x of y mastered") are deliberately not in
// the published doc, so they are not here either.
//
// This is not the "no live score" rule bending (#99): the number arrives once,
// frozen, at the report moment, with its reasoning attached — the report card,
// not a ticking counter.

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/features/milestones/milestones_page.dart'
    show difficultyLabel;
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/grading/published_report.dart';
import 'package:ai_tutor_python/services/grading/published_report_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyReportsPage extends ConsumerStatefulWidget {
  const MyReportsPage({super.key});

  @override
  ConsumerState<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends ConsumerState<MyReportsPage> {
  /// Subscribed once, by a `StreamBuilder` that sits outside every
  /// conditional branch of [build]: `pollingStream` is single-subscription,
  /// so a builder that unmounts and comes back — an empty state that fills
  /// on the next poll — would try to listen a second time and throw.
  late final Stream<List<PublishedReport>> _reports;

  @override
  void initState() {
    super.initState();
    final uid = ref.read(authServiceProvider)?.oid;
    // The shell is only reachable signed in, so the fallback is for
    // completeness — and it keeps the stream non-null, which is what lets the
    // one `StreamBuilder` be unconditional.
    _reports = uid == null
        ? Stream<List<PublishedReport>>.value(const [])
        : ref.read(publishedReportServiceProvider).watchForUser(uid);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      color: AppColors.ink0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxxl,
          AppSpacing.xxl,
          AppSpacing.xxxl,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.myReports_page_title,
              key: const Key('my-reports-title'),
              style: TextStyle(
                color: AppColors.fg,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.myReports_page_subtitle,
              style: TextStyle(
                color: AppColors.fgFaint,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: StreamBuilder<List<PublishedReport>>(
                stream: _reports,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator(minHeight: 2);
                  }
                  final reports = snapshot.data!;
                  if (reports.isEmpty) {
                    return Text(
                      l.myReports_empty,
                      key: const Key('my-reports-empty'),
                      style: TextStyle(
                        color: AppColors.fgMute,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.m),
                    itemBuilder: (context, i) =>
                        _ReportCard(report: reports[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One published report: the milestone it measured, the grade, when the
/// formula measured, the justification, the teacher's note — and, folded
/// away, the numbers behind the grade.
class _ReportCard extends StatefulWidget {
  const _ReportCard({required this.report});

  final PublishedReport report;

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = widget.report;
    return Container(
      key: Key('my-reports-card-${r.milestoneId}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.ink3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.milestoneTitle,
                  style: TextStyle(
                    color: AppColors.fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Text(
                formatDate(r.dueAt, context),
                style: TextStyle(color: AppColors.fgMute, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          // The grade, then why — never the arithmetic first.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${r.grade}',
                key: Key('my-reports-grade-${r.milestoneId}'),
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  l.myReports_grade_outOf,
                  style: TextStyle(color: AppColors.fgMute, fontSize: 13),
                ),
              ),
            ],
          ),
          // Honest about *when* the formula measured: the teacher runs the
          // batch at a moment of their choosing, so a classmate who worked
          // another week and scored higher is never a mystery.
          Text(
            l.myReports_computedAt(formatTs(r.computedAt, context)),
            key: Key('my-reports-computed-${r.milestoneId}'),
            style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
          ),
          if (r.justification.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.m),
            SelectableText(
              r.justification,
              key: Key('my-reports-justification-${r.milestoneId}'),
              style: TextStyle(
                color: AppColors.fg,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
          // A revised copy says so, right under the text that changed: the
          // wording a student read last week may not be the wording here.
          if (r.isRepublished) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l.myReports_revised(formatTs(r.updatedAt, context)),
              key: Key('my-reports-revised-${r.milestoneId}'),
              style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
            ),
          ],
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              l.myReports_note(r.note),
              key: Key('my-reports-note-${r.milestoneId}'),
              style: TextStyle(
                color: AppColors.fgMute,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('my-reports-breakdown-toggle-${r.milestoneId}'),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppColors.fgMute,
              ),
              label: Text(
                l.myReports_breakdown_title,
                style: TextStyle(color: AppColors.fgMute, fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.xxs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (_open) _Breakdown(report: r),
        ],
      ),
    );
  }
}

/// The numbers a student can check against PUNTENFORMULE §2 — collapsed by
/// default, which is the whole point (see the file header).
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.report});

  final PublishedReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = report;
    String m(double v) => v.toStringAsFixed(1);
    String frac(double v) => v.toStringAsFixed(2);
    final style = TextStyle(
      color: AppColors.fgMute,
      fontSize: 12.5,
      height: 1.55,
    );
    return Padding(
      key: Key('my-reports-breakdown-${r.milestoneId}'),
      padding: const EdgeInsets.only(
        left: AppSpacing.s,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.myReports_breakdown_mastery(m(r.mEnd)), style: style),
          Text(
            l.myReports_breakdown_fractions(frac(r.k), frac(r.u), frac(r.d)),
            style: style,
          ),
          Text(
            l.myReports_breakdown_core(r.coreCounted, r.coreTotal),
            style: style,
          ),
          Text(
            l.myReports_breakdown_extension(
              r.extensionMastered,
              r.extensionTotal,
            ),
            style: style,
          ),
          Text(
            l.myReports_breakdown_expectedLevel(
              difficultyLabel(l, r.expectedDifficulty),
            ),
            style: style,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l.myReports_breakdown_hint(r.formulaVersion),
            style: TextStyle(
              color: AppColors.fgFaint,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
