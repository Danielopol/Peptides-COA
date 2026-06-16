import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';

/// Friendly state for an HTTP 200 `input_not_coa` body.
class NotACoaView extends ConsumerWidget {
  const NotACoaView({super.key, required this.info});

  final NotACoa info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.help_outline, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text("This doesn't look like a COA",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            "We couldn't read enough text from this file to analyze it. Make sure the "
            "certificate is in focus and not blank, then try again.",
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text('Read ${info.ocrChars} characters from “${info.filename}”.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 28),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Try another file'),
            onPressed: () {
              ref.read(scanControllerProvider.notifier).reset();
              context.go('/');
            },
          ),
        ],
      ),
    );
  }
}
