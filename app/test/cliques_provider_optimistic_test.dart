// Mirror of `events_provider_optimistic_test.dart` for the cliques notifier.
// Locks in the cross-account leak fix: when bootstrapUserId differs from
// currentUserId (sign-out → sign-up case), CliquesListNotifier.build() must
// reject the bootstrap and fetch fresh.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clique_pix/core/cache/list_bootstrap_providers.dart';
import 'package:clique_pix/features/auth/presentation/auth_providers.dart';
import 'package:clique_pix/features/cliques/data/cliques_api.dart';
import 'package:clique_pix/features/cliques/domain/cliques_repository.dart';
import 'package:clique_pix/features/cliques/presentation/cliques_providers.dart';
import 'package:clique_pix/models/clique_model.dart';

const _kTestUserId = 'test-user-id';

CliqueModel _clique(String id) {
  return CliqueModel(
    id: id,
    name: 'Clique $id',
    inviteCode: 'INV-$id',
    createdByUserId: 'creator-1',
    memberCount: 1,
    createdAt: DateTime.utc(2026, 5, 6, 12),
  );
}

class _FakeRepo implements CliquesRepository {
  _FakeRepo({List<CliqueModel>? freshList}) : freshList = freshList ?? [];

  List<CliqueModel> freshList;
  int callCount = 0;

  @override
  Future<List<CliqueModel>> listCliques() async {
    callCount++;
    return freshList;
  }

  @override
  CliquesApi get api => throw UnimplementedError();
  @override
  Future<CliqueModel> createClique(String name) => throw UnimplementedError();
  @override
  Future<CliqueModel> getClique(String cliqueId) => throw UnimplementedError();
  @override
  Future<({String inviteCode, String inviteUrl})> getInviteInfo(String cliqueId) =>
      throw UnimplementedError();
  @override
  Future<CliqueModel> joinByInviteCode(String inviteCode) =>
      throw UnimplementedError();
  @override
  Future<List<CliqueMemberModel>> listMembers(String cliqueId) =>
      throw UnimplementedError();
  @override
  Future<void> leaveClique(String cliqueId) => throw UnimplementedError();
  @override
  Future<void> removeMember(String cliqueId, String userId) =>
      throw UnimplementedError();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<Override> baseOverrides({
    required List<CliqueModel>? bootstrap,
    required CliquesRepository repo,
    String? currentUserId = _kTestUserId,
    String? bootstrapUserId = _kTestUserId,
  }) =>
      [
        currentUserIdProvider.overrideWith((ref) => currentUserId),
        bootstrapUserIdProvider.overrideWithValue(bootstrapUserId),
        cliquesBootstrapProvider.overrideWithValue(bootstrap),
        cliquesRepositoryProvider.overrideWithValue(repo),
      ];

  test(
    'rejects bootstrap when bootstrapUserId differs from currentUserId',
    () async {
      final stale = [_clique('USER-A-CLIQUE')];
      final repo = _FakeRepo(freshList: []);
      final container = ProviderContainer(
        overrides: baseOverrides(
          bootstrap: stale,
          repo: repo,
          currentUserId: 'user-B',
          bootstrapUserId: 'user-A',
        ),
      );
      addTearDown(container.dispose);

      final state = await container.read(cliquesListProvider.future);
      expect(state, isEmpty,
          reason:
              'cross-account leak: User B must NOT receive User A\'s cached cliques');
      expect(repo.callCount, 1,
          reason:
              'a fresh API fetch must be made when bootstrap is rejected');
    },
  );

  test('returns empty list when currentUserId is null (signed out)',
      () async {
    final cached = [_clique('CACHED')];
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: baseOverrides(
        bootstrap: cached,
        repo: repo,
        currentUserId: null,
        bootstrapUserId: _kTestUserId,
      ),
    );
    addTearDown(container.dispose);

    final state = await container.read(cliquesListProvider.future);
    expect(state, isEmpty,
        reason: 'unauthenticated branch must return empty list, not bootstrap');
    expect(repo.callCount, 0,
        reason:
            'unauthenticated branch must not call the repo (would 401 anyway)');
  });

  test('uses bootstrap when bootstrapUserId matches currentUserId',
      () async {
    final cached = [_clique('CACHED-1'), _clique('CACHED-2')];
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: baseOverrides(bootstrap: cached, repo: repo),
    );
    addTearDown(container.dispose);

    final state = await container.read(cliquesListProvider.future);
    expect(state.map((c) => c.id), ['CACHED-1', 'CACHED-2'],
        reason: 'same-user bootstrap must be honored');
  });
}
