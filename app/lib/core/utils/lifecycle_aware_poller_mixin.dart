import 'dart:async';
import 'package:flutter/widgets.dart';

/// Drop-in mixin for [State] subclasses that need a periodic polling timer
/// which automatically pauses while the app is backgrounded and resumes
/// (with an immediate refresh) when the user returns. Eliminates
/// background-traffic amplification: a 30-second polling timer that keeps
/// firing while the app is in the background piles up requests against the
/// APIM rate limit for nothing.
///
/// Adopt by:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with LifecycleAwarePollerMixin {
///   @override
///   Duration get pollInterval => const Duration(seconds: 30);
///
///   @override
///   void onPoll() {
///     ref.invalidate(myProvider(widget.id));
///   }
/// }
/// ```
mixin LifecycleAwarePollerMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  _PollerLifecycleObserver? _observer;

  /// How often [onPoll] fires while the app is in the foreground.
  Duration get pollInterval;

  /// Called every [pollInterval] while foregrounded, AND once immediately on
  /// app resume (so users see fresh data the moment they tab back in).
  void onPoll();

  /// Set to false to disable the immediate one-shot refresh on app resume.
  /// Default true — most polled feeds want a quick refresh on focus.
  bool get refreshOnResume => true;

  @override
  void initState() {
    super.initState();
    _observer = _PollerLifecycleObserver(
      onPause: _stopPolling,
      onResume: () {
        if (!mounted) return;
        if (refreshOnResume) onPoll();
        _startPolling();
      },
    );
    WidgetsBinding.instance.addObserver(_observer!);
    _startPolling();
  }

  @override
  void dispose() {
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (mounted) onPoll();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

class _PollerLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onPause;
  final VoidCallback onResume;

  _PollerLifecycleObserver({required this.onPause, required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onPause();
        break;
      case AppLifecycleState.resumed:
        onResume();
        break;
    }
  }
}
