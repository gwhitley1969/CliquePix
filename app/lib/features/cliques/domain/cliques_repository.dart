import '../../../models/clique_model.dart';
import '../data/cliques_api.dart';

class CliquesRepository {
  final CliquesApi api;
  CliquesRepository(this.api);

  Future<CliqueModel> createClique(String name) async {
    final data = await api.createClique(name);
    return CliqueModel.fromJson(data);
  }

  Future<List<CliqueModel>> listCliques() async {
    final data = await api.listCliques();
    return data.map((e) => CliqueModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CliqueModel> getClique(String cliqueId) async {
    final data = await api.getClique(cliqueId);
    return CliqueModel.fromJson(data);
  }

  Future<({String inviteCode, String inviteUrl})> getInviteInfo(String cliqueId) async {
    final data = await api.getInviteInfo(cliqueId);
    return (
      inviteCode: data['invite_code'] as String,
      inviteUrl: data['invite_url'] as String,
    );
  }

  Future<CliqueModel> joinByInviteCode(String inviteCode) async {
    final data = await api.joinByInviteCode(inviteCode);
    return CliqueModel.fromJson(data);
  }

  Future<List<CliqueMemberModel>> listMembers(String cliqueId) async {
    final data = await api.listMembers(cliqueId);
    return data.map((e) => CliqueMemberModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> leaveClique(String cliqueId) async {
    await api.leaveClique(cliqueId);
  }

  Future<void> removeMember(String cliqueId, String userId) async {
    await api.removeMember(cliqueId, userId);
  }
}
