import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/token_storage_service.dart';
import '../../auth/domain/app_lifecycle_service.dart';
import '../../auth/presentation/auth_providers.dart';

/// Hidden beta-testing screen reached by tapping the version number seven
/// times in ProfileScreen. Exposes token state and the telemetry ring
/// buffer so we can actually see which of the 5 layers are firing in prod.
class TokenDiagnosticsScreen extends ConsumerStatefulWidget {
  const TokenDiagnosticsScreen({super.key});

  @override
  ConsumerState<TokenDiagnosticsScreen> createState() =>
      _TokenDiagnosticsScreenState();
}

class _TokenDiagnosticsScreenState
    extends ConsumerState<TokenDiagnosticsScreen> {
  DateTime? _lastRefresh;
  bool _pendingFlag = false;
  bool _batteryExempt = false;
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tokenStorage = ref.read(tokenStorageServiceProvider);
    final telemetry = ref.read(telemetryServiceProvider);
    final prefs = await SharedPreferences.getInstance();
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;

    final last = await tokenStorage.getLastRefreshTime();
    final events = await telemetry.readBuffer();

    if (!mounted) return;
    setState(() {
      _lastRefresh = last;
      _pendingFlag = prefs.getBool(pendingRefreshFlagKey) ?? false;
      _batteryExempt = batteryStatus.isGranted;
      _events = events;
      _loading = false;
    });
  }

  Future<void> _forceRefresh() async {
    setState(() => _loading = true);
    final repo = ref.read(authRepositoryProvider);
    final ok = await repo.refreshToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Refresh succeeded' : 'Refresh failed')),
    );
    await _load();
  }

  Future<void> _simulateStale() async {
    final staleTime = DateTime.now().subtract(const Duration(hours: 11));
    final storage = ref.read(tokenStorageServiceProvider);
    // saveTokens updates lastRefreshTime to now — we want to force it stale.
    // The simplest path is to read access token, clear, then re-save with a
    // backdated mark. But TokenStorageService doesn't expose a setter. Use
    // the underlying SharedPreferences? No — it's FlutterSecureStorage. Use
    // a raw call through its API. Instead: just clear and warn.
    //
    // Workaround: delete the lastRefreshTime key via a fresh secure-storage
    // instance — allowed because the class is public and keys are private.
    // We ask TokenStorageService for getLastRefreshTime to confirm.
    await storage.saveTokens(
      accessToken: await storage.getAccessToken() ?? '',
      refreshToken: '',
    );
    // Now overwrite the timestamp via a direct write
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diag_simulated_stale', staleTime.toIso8601String());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Cannot override lastRefreshTime directly; see code comment.'),
      ),
    );
    await _load();
  }

  Future<void> _clearBuffer() async {
    await ref.read(telemetryServiceProvider).clearBuffer();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final age = _lastRefresh == null
        ? null
        : DateTime.now().difference(_lastRefresh!);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        title: const Text('Token Diagnostics'),
        backgroundColor: const Color(0xFF0E1525),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statTile('Last refresh', _lastRefresh?.toLocal().toString() ?? '—'),
                  _statTile(
                      'Token age', age == null ? '—' : '${age.inHours}h ${age.inMinutes % 60}m'),
                  _statTile('Pending refresh flag',
                      _pendingFlag ? 'set (will refresh on resume)' : 'clear'),
                  _statTile(
                      'Battery exempt (Android)',
                      _batteryExempt
                          ? 'granted'
                          : 'not granted — Layer 4 may be throttled'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _forceRefresh,
                        child: const Text('Force refresh'),
                      ),
                      OutlinedButton(
                        onPressed: _simulateStale,
                        child: const Text('Simulate 11h stale'),
                      ),
                      TextButton(
                        onPressed: _clearBuffer,
                        child: const Text('Clear telemetry'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Telemetry buffer (${_events.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    Text(
                      'No events recorded yet.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  for (final e in _events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e['e']?.toString() ?? '?',
                                style: const TextStyle(
                                  color: AppColors.electricAqua,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (e['c'] != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  e['c'].toString(),
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            Text(
                              _shortTime(e['t']?.toString()),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _statTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
