import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layer 1: Battery Optimization Exemption (Android only)
/// Critical for Samsung/Xiaomi/Huawei — without this, background tasks are killed.
class BatteryOptimizationService {
  static const _dialogShownKey = 'battery_dialog_shown';

  Future<void> requestExemptionIfNeeded(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_dialogShownKey) == true) return;

    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) {
      await prefs.setBool(_dialogShownKey, true);
      return;
    }

    if (!context.mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Stay Signed In'),
        content: const Text(
          'To keep you signed in, Clique Pix needs permission to run in the background. '
          'Without this, you may need to sign in again after a few hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maybe Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    await prefs.setBool(_dialogShownKey, true);

    if (shouldRequest == true) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }
}
