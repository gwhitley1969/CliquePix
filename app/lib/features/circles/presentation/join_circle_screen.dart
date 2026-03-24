import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';
import 'circles_providers.dart';

class JoinCircleScreen extends ConsumerStatefulWidget {
  final String? inviteCode;
  const JoinCircleScreen({super.key, this.inviteCode});

  @override
  ConsumerState<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

class _JoinCircleScreenState extends ConsumerState<JoinCircleScreen> {
  late final TextEditingController _codeController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.inviteCode ?? '');
    if (widget.inviteCode != null && widget.inviteCode!.isNotEmpty) {
      _joinCircle();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinCircle() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() { _isLoading = true; _error = null; });
    try {
      final repo = ref.read(circlesRepositoryProvider);
      final circle = await repo.joinByInviteCode(code);
      ref.read(circlesListProvider.notifier).refresh();
      if (mounted) context.go('/circles/${circle.id}');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Circle')),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_add, size: 80, color: AppColors.deepBlue),
            const SizedBox(height: 24),
            Text('Join a Circle', style: AppTextStyles.heading1),
            const SizedBox(height: 8),
            Text(
              'Enter the invite code to join',
              style: AppTextStyles.body.copyWith(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Invite Code',
                hintText: 'Enter 8-character code',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 24),
            GradientButton(
              text: 'Join Circle',
              isLoading: _isLoading,
              onPressed: _joinCircle,
            ),
          ],
        ),
      ),
    );
  }
}
