import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';

/// Error state for 400 / 413 / network failures.
class ScanErrorView extends ConsumerWidget {
  const ScanErrorView({super.key, required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final unreachable = statusCode == null;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(unreachable ? Icons.wifi_off : Icons.error_outline,
              size: 64, color: HelixColors.of(context).vRed),
          const SizedBox(height: 16),
          Text(unreachable ? "Can't reach the backend" : 'That file was rejected',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
          if (statusCode != null) ...[
            const SizedBox(height: 6),
            Text('HTTP $statusCode', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to start'),
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
