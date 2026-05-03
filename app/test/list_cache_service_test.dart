import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clique_pix/core/cache/list_cache_service.dart';
import 'package:clique_pix/models/clique_model.dart';
import 'package:clique_pix/models/event_model.dart';

EventModel _event(String id, {String? cliqueId, DateTime? createdAt}) {
  final now = createdAt ?? DateTime.utc(2026, 5, 3, 12);
  return EventModel(
    id: id,
    cliqueId: cliqueId ?? 'clique-1',
    name: 'Event $id',
    createdByUserId: 'creator-1',
    retentionHours: 168,
    status: 'active',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 168)),
  );
}

CliqueModel _clique(String id) {
  return CliqueModel(
    id: id,
    name: 'Clique $id',
    inviteCode: 'INVITE-$id',
    createdByUserId: 'creator-1',
    memberCount: 3,
    createdAt: DateTime.utc(2026, 5, 1),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ListCacheService events', () {
    test('round-trip preserves the list', () async {
      final svc = ListCacheService();
      final events = [_event('a'), _event('b'), _event('c')];
      await svc.writeEvents('user-1', events);

      final read = await svc.readEvents('user-1');
      expect(read, isNotNull);
      expect(read!.length, 3);
      expect(read.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('returns null when nothing stored', () async {
      final svc = ListCacheService();
      expect(await svc.readEvents('nobody'), isNull);
    });

    test('truncates to last 50 events on write', () async {
      final svc = ListCacheService();
      final events = List.generate(75, (i) => _event('e$i'));
      await svc.writeEvents('user-1', events);
      final read = await svc.readEvents('user-1');
      expect(read!.length, 50);
      // First 50 retained.
      expect(read.first.id, 'e0');
      expect(read.last.id, 'e49');
    });

    test('corrupt JSON clears the key and returns null', () async {
      SharedPreferences.setMockInitialValues({
        'events_cache_v1_user-1': 'not valid json {{{',
      });
      final svc = ListCacheService();
      expect(await svc.readEvents('user-1'), isNull);
      // Subsequent reads continue to return null because the key was cleared.
      expect(await svc.readEvents('user-1'), isNull);
    });

    test('caches isolated per user', () async {
      final svc = ListCacheService();
      await svc.writeEvents('user-A', [_event('x')]);
      await svc.writeEvents('user-B', [_event('y'), _event('z')]);

      final aRead = await svc.readEvents('user-A');
      final bRead = await svc.readEvents('user-B');
      expect(aRead!.map((e) => e.id), ['x']);
      expect(bRead!.map((e) => e.id), ['y', 'z']);
    });
  });

  group('ListCacheService cliques', () {
    test('round-trip preserves the list', () async {
      final svc = ListCacheService();
      final cliques = [_clique('a'), _clique('b')];
      await svc.writeCliques('user-1', cliques);

      final read = await svc.readCliques('user-1');
      expect(read, isNotNull);
      expect(read!.map((c) => c.id), ['a', 'b']);
    });

    test('truncates to last 30 cliques on write', () async {
      final svc = ListCacheService();
      final cliques = List.generate(45, (i) => _clique('c$i'));
      await svc.writeCliques('user-1', cliques);
      final read = await svc.readCliques('user-1');
      expect(read!.length, 30);
    });
  });

  group('ListCacheService clears', () {
    test('clearForUser removes only that user keys', () async {
      final svc = ListCacheService();
      await svc.writeEvents('user-A', [_event('x')]);
      await svc.writeCliques('user-A', [_clique('a')]);
      await svc.writeEvents('user-B', [_event('y')]);

      await svc.clearForUser('user-A');

      expect(await svc.readEvents('user-A'), isNull);
      expect(await svc.readCliques('user-A'), isNull);
      expect(await svc.readEvents('user-B'), isNotNull);
    });

    test('clearAll wipes every user', () async {
      final svc = ListCacheService();
      await svc.writeEvents('user-A', [_event('x')]);
      await svc.writeEvents('user-B', [_event('y')]);
      await svc.writeCliques('user-C', [_clique('a')]);

      await svc.clearAll();

      expect(await svc.readEvents('user-A'), isNull);
      expect(await svc.readEvents('user-B'), isNull);
      expect(await svc.readCliques('user-C'), isNull);
    });
  });
}
