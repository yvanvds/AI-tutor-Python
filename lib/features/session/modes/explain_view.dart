import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uitleg — read-and-understand layout. Reads the active subgoal from
/// `goalSelectionProvider`, loads the linked `content` doc, and renders its
/// markdown body using the same visual language as the prototype: header
/// pill, title, code card, info callout, and footer.
class ExplainView extends ConsumerWidget {
  const ExplainView({super.key});

  static const _maxWidth = 680.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(goalSelectionProvider);
    final child = selection.activeChildGoal;
    final root = selection.activeRootGoal;

    Widget body;
    if (child == null) {
      body = const _Placeholder(
        message: 'Kies een subdoel in Leerpad om de uitleg te bekijken.',
      );
    } else if (child.contentId == null || child.contentId!.isEmpty) {
      body = _MissingContent(child: child, root: root);
    } else {
      body = _ContentView(child: child, root: root, contentId: child.contentId!);
    }

    return Container(
      color: AppColors.ink0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _ContentView extends ConsumerWidget {
  const _ContentView({
    required this.child,
    required this.root,
    required this.contentId,
  });

  final Goal child;
  final Goal? root;
  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(contentServiceProvider);
    final content = cached
        .where((c) => c.id == contentId)
        .cast<Content?>()
        .firstWhere((_) => true, orElse: () => null);

    if (content == null) {
      // Cache hasn't filled yet — fall back to a one-shot stream.
      return StreamBuilder<Content?>(
        stream: ref
            .read(contentServiceProvider.notifier)
            .watchById(contentId),
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) {
            return const _Placeholder(message: 'Lesinhoud laden…');
          }
          return _ContentBody(child: child, root: root, content: c);
        },
      );
    }
    return _ContentBody(child: child, root: root, content: content);
  }
}

class _ContentBody extends ConsumerWidget {
  const _ContentBody({
    required this.child,
    required this.root,
    required this.content,
  });

  final Goal child;
  final Goal? root;
  final Content content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubgoalHeader(child: child, root: root),
        const SizedBox(height: AppSpacing.lg),
        _Title(text: content.title),
        const SizedBox(height: AppSpacing.xl),
        ...renderMarkdownBlocks(content.body),
        const SizedBox(height: AppSpacing.xxl),
        const _Footer(),
      ],
    );
  }
}

class _MissingContent extends StatelessWidget {
  const _MissingContent({required this.child, required this.root});
  final Goal child;
  final Goal? root;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubgoalHeader(child: child, root: root),
        const SizedBox(height: AppSpacing.lg),
        _Title(text: child.title),
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.ink1,
            border: Border.all(color: AppColors.ink2),
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          ),
          child: const Text(
            'Nog geen lesinhoud beschikbaar voor dit subdoel.',
            style: TextStyle(
              color: AppColors.fgMute,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const _Footer(),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
      ),
    );
  }
}

class _SubgoalHeader extends ConsumerWidget {
  const _SubgoalHeader({required this.child, required this.root});
  final Goal child;
  final Goal? root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pill = (root?.title ?? 'Concept').toUpperCase();
    return StreamBuilder<List<Goal>>(
      stream: root == null
          ? const Stream.empty()
          : ref.read(goalsServiceProvider).streamChildren(root!.id),
      builder: (context, snap) {
        final siblings = snap.data ?? const <Goal>[];
        final idx = siblings.indexWhere((g) => g.id == child.id);
        final total = siblings.length;
        final showCounter = idx >= 0 && total > 0;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                pill,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Spacer(),
            if (showCounter)
              Text(
                '${idx + 1} / $total',
                style: AppMono.tnum(
                  size: 12,
                  weight: FontWeight.w500,
                  color: AppColors.fgFaint,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.fg,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _GhostButton(
          label: 'Vorige',
          icon: Icons.arrow_back,
          onTap: () {},
        ),
        const Spacer(),
        const Text(
          '+10 XP bij voltooien',
          style: TextStyle(
            color: AppColors.fgFaint,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        _AccentButton(
          label: 'Probeer het zelf',
          onTap: () =>
              ref.read(modeProvider.notifier).state = SessionMode.practice,
        ),
      ],
    );
  }
}

// --- Markdown rendering --------------------------------------------------

/// Renders a small, opinionated markdown subset matching the conventions
/// teachers author against:
/// * Fenced ` ```python ` blocks → "Hoe Python eraan denkt" code card.
/// * Lines starting with `> [!info]` → info callout pill.
/// * `# / ## / ###` headings → progressively smaller titles.
/// * Everything else → paragraph text (with `**bold**` and ` `code` `
///   inline runs).
List<Widget> renderMarkdownBlocks(String body) {
  final blocks = _parseBlocks(body);
  final out = <Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) out.add(const SizedBox(height: AppSpacing.lg));
    out.add(_renderBlock(blocks[i]));
  }
  return out;
}

abstract class _Block {}

class _CodeBlock extends _Block {
  _CodeBlock(this.language, this.lines);
  final String language;
  final List<String> lines;
}

class _CalloutBlock extends _Block {
  _CalloutBlock(this.kind, this.text);
  final String kind; // info | warn | …
  final String text;
}

class _HeadingBlock extends _Block {
  _HeadingBlock(this.level, this.text);
  final int level;
  final String text;
}

class _ParagraphBlock extends _Block {
  _ParagraphBlock(this.text);
  final String text;
}

List<_Block> _parseBlocks(String body) {
  final lines = body.split('\n');
  final blocks = <_Block>[];
  final paragraph = StringBuffer();

  void flushParagraph() {
    final t = paragraph.toString().trim();
    if (t.isNotEmpty) blocks.add(_ParagraphBlock(t));
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trimLeft();

    // Fenced code block. Accepts `​```python`, `​```{python}` (Quarto style),
    // and bare `​```` openers.
    final fenceMatch = RegExp(r'^```\s*(.*?)\s*$').firstMatch(trimmed);
    if (fenceMatch != null) {
      flushParagraph();
      var lang = fenceMatch.group(1) ?? '';
      if (lang.startsWith('{') && lang.endsWith('}')) {
        lang = lang.substring(1, lang.length - 1);
      }
      final codeLines = <String>[];
      i++;
      while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
        codeLines.add(lines[i]);
        i++;
      }
      blocks.add(_CodeBlock(lang, codeLines));
      if (i < lines.length) i++; // consume closing fence
      continue;
    }

    // Callout: `> [!info] body...` (continuation lines also starting with `>`)
    final calloutMatch =
        RegExp(r'^>\s*\[!(\w+)\]\s*(.*)$').firstMatch(trimmed);
    if (calloutMatch != null) {
      flushParagraph();
      final kind = calloutMatch.group(1)!.toLowerCase();
      final buf = StringBuffer(calloutMatch.group(2) ?? '');
      i++;
      while (i < lines.length) {
        final cont = RegExp(r'^>\s?(.*)$').firstMatch(lines[i].trimLeft());
        if (cont == null) break;
        buf.write('\n${cont.group(1) ?? ''}');
        i++;
      }
      blocks.add(_CalloutBlock(kind, buf.toString().trim()));
      continue;
    }

    // Heading
    final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (headingMatch != null) {
      flushParagraph();
      final level = headingMatch.group(1)!.length;
      final text = headingMatch.group(2)!.trim();
      blocks.add(_HeadingBlock(level, text));
      i++;
      continue;
    }

    // Blank line ends a paragraph.
    if (trimmed.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    if (paragraph.isNotEmpty) paragraph.write('\n');
    paragraph.write(line);
    i++;
  }
  flushParagraph();
  return blocks;
}

Widget _renderBlock(_Block block) {
  if (block is _CodeBlock) return _CodeCard(block: block);
  if (block is _CalloutBlock) return _Callout(block: block);
  if (block is _HeadingBlock) return _Heading(block: block);
  if (block is _ParagraphBlock) return _Paragraph(text: block.text);
  return const SizedBox.shrink();
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.block});
  final _CodeBlock block;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lgPlus,
        vertical: AppSpacing.md,
      ),
      child: SelectableText(
        block.lines.join('\n'),
        style: AppMono.code(color: AppColors.fg, size: 13),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.block});
  final _CalloutBlock block;

  @override
  Widget build(BuildContext context) {
    final color = switch (block.kind) {
      'warn' || 'warning' => AppColors.danger,
      _ => AppColors.accent3,
    };
    final icon = switch (block.kind) {
      'warn' || 'warning' => Icons.warning_amber_outlined,
      _ => Icons.info_outline,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              block.text,
              style: const TextStyle(
                color: AppColors.fg,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.block});
  final _HeadingBlock block;

  @override
  Widget build(BuildContext context) {
    final size = switch (block.level) {
      1 => 22.0,
      2 => 18.0,
      _ => 15.0,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppColors.fg,
            fontSize: size,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          children: _inlineSpans(block.text, codeSize: size - 2),
        ),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.fg,
          fontSize: 14,
          height: 1.55,
        ),
        children: _inlineSpans(text),
      ),
    );
  }
}

List<InlineSpan> _inlineSpans(String text, {double codeSize = 13}) {
  // Tokenises `**bold**` and `` `code` `` runs; everything else is plain.
  final out = <InlineSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
  var cursor = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > cursor) {
      out.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    if (m.group(1) != null) {
      out.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
    } else if (m.group(2) != null) {
      out.add(TextSpan(
        text: m.group(2),
        style: AppMono.code(color: AppColors.accent, size: codeSize),
      ));
    }
    cursor = m.end;
  }
  if (cursor < text.length) {
    out.add(TextSpan(text: text.substring(cursor)));
  }
  return out;
}

// --- Buttons (unchanged from prototype) ----------------------------------

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.ink2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.fgMute),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.fgMute,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentButton extends StatefulWidget {
  const _AccentButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: _hovering
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.06),
                    AppColors.accent,
                  )
                : AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward,
                size: 14,
                color: AppColors.ink0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
