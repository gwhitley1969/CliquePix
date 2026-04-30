import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dm/domain/dm_realtime_service.dart';
import '../features/dm/presentation/dm_providers.dart';
import '../features/events/presentation/events_providers.dart';
import '../features/notifications/presentation/notifications_providers.dart';
import '../services/telemetry_service.dart';

/// Subscribes to realtime Web PubSub events that affect cached Riverpod
/// providers and invalidates them so the next read fetches fresh data.
///
/// Today this handles `new_event` (a clique member created an event — Home
/// dashboard and the per-clique events list both need to refresh). Wired
/// into `ShellScreen` so the subscription lives for the entire signed-in
/// session, regardless of which bottom-tab branch is active.
///
/// The subscription is global to Riverpod — invalidation works even when
/// the user is on an out-of-shell screen (event detail, camera, video
/// player). The next time they navigate back to a screen reading
/// `allEventsListProvider`, the data is already fresh.
class RealtimeProviderInvalidator extends ConsumerStatefulWidget {
  final Widget child;

  const RealtimeProviderInvalidator({required this.child, super.key});

  @override
  ConsumerState<RealtimeProviderInvalidator> createState() =>
      _RealtimeProviderInvalidatorState();
}

class _RealtimeProviderInvalidatorState
    extends ConsumerState<RealtimeProviderInvalidator> {
  StreamSubscription<NewEventEvent>? _newEventSub;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(dmRealtimeServiceProvider);
    _newEventSub = svc.onNewEvent.listen(_handleNewEvent);
  }

  void _handleNewEvent(NewEventEvent evt) {
    ref.invalidate(allEventsListProvider);
    ref.invalidate(eventsListProvider(evt.cliqueId));
    ref.invalidate(notificationsListProvider);
    try {
      ref.read(telemetryServiceProvider).record('new_event_received', extra: {
        'eventId': evt.eventId,
        'cliqueId': evt.cliqueId,
      });
    } catch (_) {
      // telemetry is best-effort
    }
  }

  @override
  void dispose() {
    _newEventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
