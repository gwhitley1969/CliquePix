import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/gradient_button.dart';
import 'cliques_providers.dart';

class CreateCliqueScreen extends ConsumerStatefulWidget {
  const CreateCliqueScreen({super.key});

  @override
  ConsumerState<CreateCliqueScreen> createState() => _CreateCliqueScreenState();
}

class _CreateCliqueScreenState extends ConsumerState<CreateCliqueScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createClique() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final clique = await ref.read(cliquesListProvider.notifier).createClique(name);
      if (mounted) context.go('/cliques/${clique.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
          'Create Clique',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Section label
            Text(
              'Clique Name',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            // Dark-themed text field
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'e.g., Family, College Friends, Work Team',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
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
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              cursorColor: AppColors.electricAqua,
            ),
            const SizedBox(height: 8),
            Text(
              'This is the group your friends will join to share photos',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
            ),
            const Spacer(),
            GradientButton(
              text: 'Create Clique',
              isLoading: _isLoading,
              onPressed: _nameController.text.trim().isNotEmpty ? _createClique : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
