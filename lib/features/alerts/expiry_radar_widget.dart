import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/document_model.dart';

class ExpiryRadarWidget extends StatelessWidget {
  final List<DocumentModel> expiringDocs;
  final Function(DocumentModel)? onDocTap;

  const ExpiryRadarWidget({
    super.key,
    required this.expiringDocs,
    this.onDocTap,
  });

  @override
  Widget build(BuildContext context) {
    // Count documents in each category
    final now = DateTime.now();
    int urgentCount = 0;
    int upcomingCount = 0;
    int lifetimeCount = 0;

    for (final doc in expiringDocs) {
      if (doc.expiryDate == null) {
        lifetimeCount++;
      } else {
        final days = doc.expiryDate!.difference(now).inDays;
        if (days <= 7) {
          urgentCount++;
        } else if (days <= 60) {
          upcomingCount++;
        } else {
          lifetimeCount++;
        }
      }
    }

    // Default aesthetic values if vault is fresh
    if (urgentCount == 0 && upcomingCount == 0 && lifetimeCount == 0) {
      urgentCount = 1;
      upcomingCount = 2;
      lifetimeCount = 9;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Glow
          Container(
            width: 280,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFED7AA).withValues(alpha: 0.25),
                  const Color(0xFFBBF7D0).withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Multi-Ring Concentric Radar with Ticks
          SizedBox(
            width: 270,
            height: 240,
            child: CustomPaint(
              painter: _ConcentricRadarPainter(),
            ),
          ),

          // Legend Badges positioned over the concentric rings
          Positioned(
            top: 28,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Expired',
                        style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Due in 1d',
                        style: TextStyle(color: Color(0xFFDC2626), fontSize: 9.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Urgent for Passport/Insurances',
                  style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          Positioned(
            top: 92,
            right: 38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Expiring in 30d',
                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'eg. ID renewals',
                  style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          Positioned(
            top: 148,
            right: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Lifetime Valid',
                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Like PAN/Aadhaar',
                  style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcentricRadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.42, size.height * 0.52);

    // 1. Draw outer radial clock tick marks
    final tickRadius = size.width * 0.48;
    final tickPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0;

    const totalTicks = 80;
    for (int i = 0; i < totalTicks; i++) {
      final angle = (i * 2 * math.pi) / totalTicks;
      final isMajor = i % 5 == 0;
      final innerR = isMajor ? tickRadius - 6 : tickRadius - 3;
      final outerR = tickRadius;

      final p1 = Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle));
      final p2 = Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle));
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 2. Outer Ring: Expired / Urgent (Coral Red Arc)
    final outerRect = Rect.fromCircle(center: center, radius: 95);
    final outerTrackPaint = Paint()
      ..color = const Color(0xFFFEE2E2).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    canvas.drawArc(outerRect, 0, 2 * math.pi, false, outerTrackPaint);

    final outerArcPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFCA5A5), Color(0xFFEF4444)],
      ).createShader(outerRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13;
    canvas.drawArc(outerRect, math.pi * 0.8, math.pi * 0.95, false, outerArcPaint);

    // 3. Middle Ring: 30-Day Expiry (Amber Orange Arc)
    final midRect = Rect.fromCircle(center: center, radius: 72);
    final midTrackPaint = Paint()
      ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    canvas.drawArc(midRect, 0, 2 * math.pi, false, midTrackPaint);

    final midArcPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
      ).createShader(midRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13;
    canvas.drawArc(midRect, math.pi * 0.85, math.pi * 0.85, false, midArcPaint);

    // 4. Inner Ring: Lifetime Valid (Emerald Green Arc)
    final innerRect = Rect.fromCircle(center: center, radius: 49);
    final innerTrackPaint = Paint()
      ..color = const Color(0xFFD1FAE5).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    canvas.drawArc(innerRect, 0, 2 * math.pi, false, innerTrackPaint);

    final innerArcPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF6EE7B7), Color(0xFF10B981)],
      ).createShader(innerRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13;
    canvas.drawArc(innerRect, math.pi * 0.9, math.pi * 0.75, false, innerArcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
