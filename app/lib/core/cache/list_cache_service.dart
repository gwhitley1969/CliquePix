import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/clique_model.dart';
import '../../models/event_model.dart';

// Stale-while-revalidate cache for the event + clique lists. Keys are
// versioned (so a model-shape change invalidates safely) and user-scoped (so
// signing in as a different account on the same device never sees the prior
// user's data). Reads are wrapped in try/catch — any deserialization error
// clears the key and returns null. Writes are capped at the limits below.

const _kEventsKeyPrefix = 'events_cache_v1_';
const _kCliquesKeyPrefix = 'cliques_cache_v1_';
const _kMaxEventsCached = 50;
const _kMaxCliquesCached = 30;

class ListCacheService {
  String _eventsKey(String userId) => '$_kEventsKeyPrefix$userId';
  String _cliquesKey(String userId) => '$_kCliquesKeyPrefix$userId';

  Future<List<EventModel>?> readEvents(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_eventsKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ListCacheService] events deserialize failed: $e — clearing');
      await prefs.remove(_eventsKey(userId));
      return null;
    }
  }

  Future<void> writeEvents(String userId, List<EventModel> events) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = events.length > _kMaxEventsCached
        ? events.sublist(0, _kMaxEventsCached)
        : events;
    final encoded = jsonEncode(capped.map((e) => e.toJson()).toList());
    await prefs.setString(_eventsKey(userId), encoded);
  }

  Future<List<CliqueModel>?> readCliques(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cliquesKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((c) => CliqueModel.fromJson(c as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ListCacheService] cliques deserialize failed: $e — clearing');
      await prefs.remove(_cliquesKey(userId));
      return null;
    }
  }

  Future<void> writeCliques(String userId, List<CliqueModel> cliques) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = cliques.length > _kMaxCliquesCached
        ? cliques.sublist(0, _kMaxCliquesCached)
        : cliques;
    final encoded = jsonEncode(capped.map((c) => c.toJson()).toList());
    await prefs.setString(_cliquesKey(userId), encoded);
  }

  Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventsKey(userId));
    await prefs.remove(_cliquesKey(userId));
  }

  // Belt-and-suspenders: clears any list cache for any user. Used on
  // account-delete and as a defensive measure when the signed-in user id
  // is unknown.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final toRemove = prefs.getKeys().where(
          (k) =>
              k.startsWith(_kEventsKeyPrefix) ||
              k.startsWith(_kCliquesKeyPrefix),
        );
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }
}

final listCacheServiceProvider = Provider<ListCacheService>((ref) {
  return ListCacheService();
});
