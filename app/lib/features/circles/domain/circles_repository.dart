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
    // The API expects circleId, but we look up by invite code
    // The join endpoint accepts invite_code in the body
    // We need to find the circle first or the API handles it
    final data = await api.joinCircle('_', inviteCode);
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
