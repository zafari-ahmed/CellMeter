import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Dialogs with correctly sized action buttons.
///
/// The app's global button themes set a 50dp minimum height and a 15sp label,
/// which is right for a full-width primary action at the bottom of a form and
/// far too heavy inside a dialog, where two buttons sit side by side and
/// should read as a choice rather than as two slabs. Flutter has no way to
/// scope a button theme to dialogs, so the sizing is applied here and every
/// dialog in the app goes through this helper.
abstract final class AppDialog {
  /// Compact action-button metrics, shared by both buttons so they line up.
  static ButtonStyle _actionStyle(BuildContext context) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  /// Asks the user to confirm something, returning true only on an explicit
  /// yes. Dismissing the dialog counts as no.
  ///
  /// [destructive] colours the confirm button and is for actions that cannot
  /// be undone, so the weight of the choice is visible before it is made.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
        ),
        content: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: _actionStyle(context).copyWith(
              foregroundColor: WidgetStatePropertyAll(
                theme.colorScheme.onSurfaceVariant,
              ),
            ),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: _actionStyle(context).copyWith(
              backgroundColor: WidgetStatePropertyAll(
                destructive ? AppColors.critical : AppColors.primary,
              ),
              foregroundColor: WidgetStatePropertyAll(
                destructive ? Colors.white : AppColors.navyDeep,
              ),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// A dialog that only tells the user something.
  static Future<void> inform(
    BuildContext context, {
    required String title,
    required String message,
    String dismissLabel = 'Got it',
  }) {
    final theme = Theme.of(context);

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
        ),
        content: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: _actionStyle(context).copyWith(
              backgroundColor: const WidgetStatePropertyAll(AppColors.primary),
              foregroundColor: const WidgetStatePropertyAll(AppColors.navyDeep),
            ),
            child: Text(dismissLabel),
          ),
        ],
      ),
    );
  }
}
