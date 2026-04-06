import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../widgets/gradient_button.dart';
import 'cliques_providers.dart';

class JoinCliqueScreen extends ConsumerStatefulWidget {
  final String inviteCode;
  const JoinCliqueScreen({super.key, required this.inviteCode});

  @override
  ConsumerState<JoinCliqueScreen> createState() => _JoinCliqueScreenState();
}

class _JoinCliqueScreenState extends ConsumerState<JoinCliqueScreen> {
  late final TextEditingController _codeController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.inviteCode);
    if (widget.inviteCode.isNotEmpty) {
      _joinClique();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinClique() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() { _isLoading = true; _error = null; });
    try {
      final repo = ref.read(cliquesRepositoryProvider);
      final clique = await repo.joinByInviteCode(code);
      ref.read(cliquesListProvider.notifier).refresh();
      ref.invalidate(cliqueDetailProvider(clique.id));
      ref.invalidate(cliqueMembersProvider(clique.id));
      if (mounted) context.go('/cliques/${clique.id}');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: const Text(
          'Join Clique',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.primary.scale(0.25),
              ),
              child: const Icon(Icons.group_add_rounded, size: 40, color: AppColors.electricAqua),
            ),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
              child: const Text(
                'Join a Clique',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the invite code to join',
              style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Enter code',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  letterSpacing: 1,
                  fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.electricAqua, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              cursorColor: AppColors.electricAqua,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            GradientButton(
              text: 'Join Clique',
              isLoading: _isLoading,
              onPressed: _joinClique,
            ),
          ],
        ),
      ),
    );
  }
}
