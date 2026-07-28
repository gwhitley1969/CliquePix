/// Short, log-safe summary of an error for telemetry.
///
/// SINGLE SOURCE OF TRUTH — used by `main.dart` (bootstrap catch blocks) and by
/// the WorkManager background isolate in `background_token_service.dart`
/// (Layer-4 `wm_refresh_failed` telemetry). Covered by
/// `test/brief_error_test.dart`.
///
/// MUST NOT throw — it runs inside catch blocks whose whole purpose is to keep
/// the caller alive on failure. History (PR #24, then the 2026-07 duplicate):
/// the original bounded the substring by `s.length` (the FULL multi-line
/// string) but applied it to `s.split('\n').first` (the first line only) — when
/// the total exceeded 64 chars while the first line was shorter,
/// `substring(0, 64)` threw RangeError on a shorter string and escaped the
/// catch. PR #24 fixed the copy in `main.dart` (where it aborted `main()`
/// before `runApp()` — a blank-screen launch crash) but missed a duplicated
/// copy in the WorkManager isolate, where the same throw destroyed the very
/// `wm_refresh_failed` telemetry that would have reported the failure. Fixed
/// by extraction 2026-07-28 (vc15). Bound by the FIRST LINE's own length.
String briefError(Object e) {
  final s = e.toString();
  final match = RegExp(r'AADSTS\d{5,6}').firstMatch(s);
  if (match != null) return match.group(0)!;
  final first = s.split('\n').first;
  return first.length > 64 ? first.substring(0, 64) : first;
}
