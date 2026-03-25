import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/circle_model.dart';
import '../domain/circles_repository.dart';
import '../data/circles_api.dart';
import '../../../services/api_client.dart';

final circlesApiProvider = Provider<CirclesApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CirclesApi(apiClient.dio);
});

final circlesRepositoryProvider = Provider<CirclesRepository>((ref) {
  return CirclesRepository(ref.watch(circlesApiProvider));
});

final circlesListProvider = AsyncNotifierProvider<CirclesListNotifier, List<CircleModel>>(() {
  return CirclesListNotifier();
});

class CirclesListNotifier extends AsyncNotifier<List<CircleModel>> {
  @override
  Future<List<CircleModel>> build() async {
    final repo = ref.watch(circlesRepositoryProvider);
    return repo.listCircles();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(circlesRepositoryProvider).listCircles());
  }

  Future<CircleModel> createCircle(String name) async {
    final repo = ref.read(circlesRepositoryProvider);
    final circle = await repo.createCircle(name);
    await refresh();
    return circle;
  }
}

final circleDetailProvider = FutureProvider.family<CircleModel, String>((ref, circleId) async {
  final repo = ref.watch(circlesRepositoryProvider);
  return repo.getCircle(circleId);
});

final circleMembersProvider = FutureProvider.family<List<CircleMemberModel>, String>((ref, circleId) async {
  final repo = ref.watch(circlesRepositoryProvider);
  return repo.listMembers(circleId);
});
