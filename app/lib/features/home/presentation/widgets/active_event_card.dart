import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/event_model.dart';

class ActiveEventCard extends StatelessWidget {
  final EventModel event;

  const ActiveEventCard({super.key, required this.event});

  String get _timeRemaining {
    if (event.isExpired) return 'Expired';
    final diff = event.expiresAt.difference(DateTime.now());
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return hours > 0 ? '${diff.inDays}d ${hours}h remaining' : '${diff.inDays}d remaining';
    }
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return mins > 0 ? '${diff.inHours}h ${mins}m remaining' : '${diff.inHours}h remaining';
    }
    return '${diff.inMinutes}m remaining';
  }

  List<Color> get _statusColors {
    if (event.isExpired) return [const Color(0xFF6B7280), const Color(0xFF374151)];
    if (event.isExpiringSoon) return [AppColors.warning, const Color(0xFFEF4444)];
    return [AppColors.electricAqua, AppColors.deepBlue];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/events/${event.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  colors[0].withValues(alpha: 0.1),
                  colors[1].withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: colors[0].withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: event name + expiring badge
                  Row(
                    children: [
                      // Event icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          event.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (event.isExpiringSoon)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.warning.withValues(alpha: 0.15),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'Ending soon',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Clique info row
                  if (event.cliqueName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.group_rounded, size: 14, color: colors[0].withValues(alpha: 0.6)),
                          const SizedBox(width: 5),
                          Text(
                            event.cliqueName!,
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          if (event.memberCount != null) ...[
                            Text(
                              ' \u00b7 ${event.memberCount} members',
                              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  // Timer + photos row
                  Row(
                    children: [
                      Icon(
                        event.isExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
                        size: 14,
                        color: colors[0].withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _timeRemaining,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors[0].withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.photo_rounded, size: 14, color: Colors.white.withValues(alpha: 0.35)),
                      const SizedBox(width: 5),
                      Text(
                        '${event.photoCount} photos',
                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: colors[0].withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
