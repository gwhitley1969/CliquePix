import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../models/circle_model.dart';
import '../../circles/presentation/circles_providers.dart';
import 'events_providers.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  final String? circleId;
  const CreateEventScreen({super.key, this.circleId});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _newCircleNameController = TextEditingController();
  int _retentionHours = AppConstants.defaultDuration;
  String? _selectedCircleId;
  bool _creatingNewCircle = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedCircleId = widget.circleId;
    _nameController.addListener(() => setState(() {}));
    _newCircleNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _newCircleNameController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_nameController.text.trim().isEmpty) return false;
    if (_creatingNewCircle) return _newCircleNameController.text.trim().isNotEmpty;
    return _selectedCircleId != null;
  }

  Future<void> _createEvent() async {
    if (!_canSubmit) return;

    setState(() => _isLoading = true);
    try {
      String circleId;

      if (_creatingNewCircle) {
        final circle = await ref.read(circlesListProvider.notifier).createCircle(
          _newCircleNameController.text.trim(),
        );
        circleId = circle.id;
      } else {
        circleId = _selectedCircleId!;
      }

      final repo = ref.read(eventsRepositoryProvider);
      final event = await repo.createEvent(
        circleId,
        _nameController.text.trim(),
        _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        _retentionHours,
      );

      // Refresh events list
      ref.read(allEventsListProvider.notifier).refresh();

      if (mounted) {
        context.push(
          '/events/${event.id}',
          extra: _creatingNewCircle
              ? {'circleId': circleId, 'circleName': _newCircleNameController.text.trim()}
              : null,
        );
      }
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
    final circlesAsync = ref.watch(circlesListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: ShaderMask(
          shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
          child: const Text(
            'Create Event',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Event name
            _SectionLabel(text: 'Event Name'),
            const SizedBox(height: 8),
            _DarkTextField(
              controller: _nameController,
              hintText: 'e.g., Beach Day, Birthday Party',
              maxLength: 100,
              autofocus: true,
            ),
            const SizedBox(height: 20),

            // Description
            _SectionLabel(text: 'Description (optional)'),
            const SizedBox(height: 8),
            _DarkTextField(
              controller: _descriptionController,
              hintText: "What's this event about?",
              maxLength: 500,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // Duration
            _SectionLabel(text: 'Duration'),
            const SizedBox(height: 4),
            Text(
              'Photos auto-delete from the cloud after this period',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 12),
            _DarkDurationPicker(
              selectedHours: _retentionHours,
              onChanged: (hours) => setState(() => _retentionHours = hours),
            ),
            const SizedBox(height: 24),

            // Circle picker
            _SectionLabel(text: 'Circle'),
            const SizedBox(height: 4),
            Text(
              'Choose which friend group to share with',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 12),
            circlesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.electricAqua),
                ),
              ),
              error: (err, _) => Text(err.toString(), style: const TextStyle(color: AppColors.error)),
              data: (circles) => _CirclePicker(
                circles: circles,
                selectedCircleId: _selectedCircleId,
                creatingNew: _creatingNewCircle,
                newCircleController: _newCircleNameController,
                onSelectCircle: (id) => setState(() {
                  _selectedCircleId = id;
                  _creatingNewCircle = false;
                }),
                onCreateNew: () => setState(() {
                  _selectedCircleId = null;
                  _creatingNewCircle = true;
                }),
              ),
            ),
            const SizedBox(height: 40),

            // Submit button
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: _canSubmit ? AppGradients.primary : null,
                color: _canSubmit ? null : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _canSubmit
                    ? [BoxShadow(color: AppColors.deepBlue.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isLoading ? null : (_canSubmit ? _createEvent : null),
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Text(
                            'Create Event',
                            style: TextStyle(
                              color: _canSubmit ? Colors.white : Colors.white.withValues(alpha: 0.3),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;

  const _DarkTextField({
    required this.controller,
    required this.hintText,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.electricAqua, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _DarkDurationPicker extends StatelessWidget {
  final int selectedHours;
  final ValueChanged<int> onChanged;

  const _DarkDurationPicker({required this.selectedHours, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: AppConstants.durationPresets.map((hours) {
        final isSelected = hours == selectedHours;
        final label = AppConstants.durationLabels[hours] ?? '$hours h';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onChanged(hours),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: isSelected ? AppGradients.primary : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CirclePicker extends StatelessWidget {
  final List<CircleModel> circles;
  final String? selectedCircleId;
  final bool creatingNew;
  final TextEditingController newCircleController;
  final ValueChanged<String> onSelectCircle;
  final VoidCallback onCreateNew;

  const _CirclePicker({
    required this.circles,
    required this.selectedCircleId,
    required this.creatingNew,
    required this.newCircleController,
    required this.onSelectCircle,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Existing circles
        ...circles.map((circle) {
          final isSelected = circle.id == selectedCircleId && !creatingNew;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onSelectCircle(circle.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isSelected ? AppColors.deepBlue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: isSelected ? AppColors.deepBlue.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? AppColors.deepBlue : Colors.white.withValues(alpha: 0.3),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        circle.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${circle.memberCount} member${circle.memberCount != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        // Create new circle option
        GestureDetector(
          onTap: onCreateNew,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: creatingNew ? AppColors.violetAccent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: creatingNew ? AppColors.violetAccent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
                width: creatingNew ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  creatingNew ? Icons.radio_button_checked : Icons.add_circle_outline,
                  color: creatingNew ? AppColors.violetAccent : Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Create New Circle',
                  style: TextStyle(
                    color: creatingNew ? Colors.white : Colors.white.withValues(alpha: 0.6),
                    fontWeight: creatingNew ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),

        // New circle name field
        if (creatingNew) ...[
          const SizedBox(height: 12),
          _DarkTextField(
            controller: newCircleController,
            hintText: 'Circle name, e.g., College Friends',
            maxLength: 100,
            autofocus: true,
          ),
        ],
      ],
    );
  }
}
