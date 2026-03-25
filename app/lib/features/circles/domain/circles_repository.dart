import '../../../models/circle_model.dart';
import '../data/circles_api.dart';

class CirclesRepository {
  final CirclesApi api;
  CirclesRepository(this.api);

  Future<CircleModel> createCircle(String name) async {
    final data = await api.createCircle(name);
    return CircleModel.fromJson(data);
  }

  Future<List<CircleModel>> listCircles() async {
    final data = await api.listCircles();
    return data.map((e) => CircleModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CircleModel> getCircle(String circleId) async {
    final data = await api.getCircle(circleId);
    return CircleModel.fromJson(data);
  }

  Future<({String inviteCode, String inviteUrl})> getInviteInfo(String circleId) async {
    final data = await api.getInviteInfo(circleId);
    return (
      inviteCode: data['invite_code'] as String,
      inviteUrl: data['invite_url'] as String,
    );
  }

  Future<CircleModel> joinByInviteCode(String inviteCode) async {
    final data = await api.joinByInviteCode(inviteCode);
    return CircleModel.fromJson(data);
  }

  Future<List<CircleMemberModel>> listMembers(String circleId) async {
    final data = await api.listMembers(circleId);
    return data.map((e) => CircleMemberModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> leaveCircle(String circleId) async {
    await api.leaveCircle(circleId);
  }
}
