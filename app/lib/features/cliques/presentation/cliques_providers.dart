import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/last_refresh_error_provider.dart';
import '../../../core/cache/list_bootstrap_providers.dart';
import '../../../core/cache/list_cache_service.dart';
import '../../../models/clique_model.dart';
import '../../../services/api_client.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/cliques_api.dart';
import '../domain/cliques_repository.dart';

final cliquesApiProvider = Provider<CliquesApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CliquesApi(apiClient.dio);
});

final cliquesRepositoryProvider = Provider<CliquesRepository>((ref) {
  return CliquesRepository(ref.watch(cliquesApiProvider));
});

final cliquesListProvider =
    AsyncNotifierProvider<CliquesListNotifier, List<CliqueModel>>(() {
  return CliquesListNotifier();
});

class CliquesListNotifier extends AsyncNotifier<List<CliqueModel>> {
  @override
  Future<List<CliqueModel>> build() async {
    final cached = ref.read(cliquesBootstrapProvider);
    if (cached != null) {
      Future.microtask(_refreshSilently);
      return cached;
    }
    return ref.read(cliquesRepositoryProvider).listCliques();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(cliquesRepositoryProvider).listCliques(),
    );
    if (state.hasValue) {
      ref.read(cliquesRefreshErrorProvider.notifier).state = null;
      await _writeCache(state.requireValue);
    }
  }

  Future<void> _refreshSilently() async {
    List<CliqueModel> fresh;
    try {
      fresh = await ref.read(cliquesRepositoryProvider).listCliques();
    } catch (e) {
      debugPrint('[CliquesListNotifier] silent refresh failed: $e');
      ref.read(cliquesRefreshErrorProvider.notifier).state = e;
      return;
    }
    state = AsyncData(fresh);
    ref.read(cliquesRefreshErrorProvider.notifier).state = null;
    try {
      await _writeCache(fresh);
    } catch (e) {
      debugPrint('[CliquesListNotifier] cache write skipped: $e');
    }
  }

  Future<void> _writeCache(List<CliqueModel> cliques) async {
    final auth = ref.read(authStateProvider);
    if (auth is! AuthAuthenticated) return;
    await ref
        .read(listCacheServiceProvider)
        .writeCliques(auth.user.id, cliques);
  }

  Future<CliqueModel> createClique(String name) async {
    final repo = ref.read(cliquesRepositoryProvider);
    final clique = await repo.createClique(name);
    await refresh();
    return clique;
  }
}

final cliqueDetailProvider =
    FutureProvider.family<CliqueModel, String>((ref, cliqueId) async {
  final repo = ref.watch(cliquesRepositoryProvider);
  return repo.getClique(cliqueId);
});

final cliqueMembersProvider = FutureProvider.family<List<CliqueMemberModel>,
    String>((ref, cliqueId) async {
  final repo = ref.watch(cliquesRepositoryProvider);
  return repo.listMembers(cliqueId);
});
