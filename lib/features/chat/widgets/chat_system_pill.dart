import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Centered italic pill with a dashed border for system events.
class ChatSystemPill extends StatelessWidget {
  const ChatSystemPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: DottedBorder(
          color: AppColors.ink3,
          radius: AppRadius.pill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.fgFaint,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight dashed-border container — avoids pulling in another package
/// just for the system message pill.
class DottedBorder extends StatelessWidget {
  const DottedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 10,
    this.dashWidth = 3,
    this.dashSpace = 3,
    this.strokeWidth = 1,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: color,
        radius: radius,
        dashWidth: dashWidth,
        dashSpace: dashSpace,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashSpace,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      dashWidth != oldDelegate.dashWidth ||
      dashSpace != oldDelegate.dashSpace ||
      strokeWidth != oldDelegate.strokeWidth;
}
