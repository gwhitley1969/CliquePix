import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';
import '../../../widgets/duration_picker.dart';
import 'events_providers.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  final String circleId;
  const CreateEventScreen({super.key, required this.circleId});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _retentionHours = AppConstants.defaultDuration;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createEvent() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(eventsRepositoryProvider);
      final event = await repo.createEvent(
        widget.circleId,
        name,
        _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        _retentionHours,
      );
      if (mounted) context.go('/events/${event.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Event')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Event Name',
                hintText: 'e.g., Beach Day, Birthday Party',
              ),
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What\'s this event about?',
              ),
              maxLength: 500,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            const Text('Duration', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Photos will auto-delete from the cloud after this period',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 12),
            DurationPicker(
              selectedHours: _retentionHours,
              onChanged: (hours) => setState(() => _retentionHours = hours),
            ),
            const SizedBox(height: 48),
            GradientButton(
              text: 'Create Event',
              isLoading: _isLoading,
              onPressed: _createEvent,
            ),
          ],
        ),
      ),
    );
  }
}
