import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/clique_model.dart';
import '../domain/cliques_repository.dart';
import '../data/cliques_api.dart';
import '../../../services/api_client.dart';

final cliquesApiProvider = Provider<CliquesApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CliquesApi(apiClient.dio);
});

final cliquesRepositoryProvider = Provider<CliquesRepository>((ref) {
  return CliquesRepository(ref.watch(cliquesApiProvider));
});

final cliquesListProvider = AsyncNotifierProvider<CliquesListNotifier, List<CliqueModel>>(() {
  return CliquesListNotifier();
});

class CliquesListNotifier extends AsyncNotifier<List<CliqueModel>> {
  @override
  Future<List<CliqueModel>> build() async {
    final repo = ref.watch(cliquesRepositoryProvider);
    return repo.listCliques();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(cliquesRepositoryProvider).listCliques());
  }

  Future<CliqueModel> createClique(String name) async {
    final repo = ref.read(cliquesRepositoryProvider);
    final clique = await repo.createClique(name);
    await refresh();
    return clique;
  }
}

final cliqueDetailProvider = FutureProvider.family<CliqueModel, String>((ref, cliqueId) async {
  final repo = ref.watch(cliquesRepositoryProvider);
  return repo.getClique(cliqueId);
});

final cliqueMembersProvider = FutureProvider.family<List<CliqueMemberModel>, String>((ref, cliqueId) async {
  final repo = ref.watch(cliquesRepositoryProvider);
  return repo.listMembers(cliqueId);
});
