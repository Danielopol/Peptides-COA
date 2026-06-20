import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/verdict.dart';
import '../../providers/providers.dart';
import '../shared/widgets/page_body.dart';

/// Scan history, loaded from Supabase (`scans`) for the signed-in user.
/// Persistent across sessions and devices.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(historyProvider),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _empty(scheme, 'Couldn’t load history', 'Pull to refresh and try again.'),
        data: (history) => history.isEmpty
            ? _empty(scheme, 'No scans yet', 'Your verified COAs are saved here, across sessions.')
            : PageBody(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Column(
                  children: [
                    for (final r in history)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            VerdictStyle.authenticity(r.authenticity.label).icon,
                            color: VerdictStyle.authenticity(r.authenticity.label).color,
                          ),
                          title: Text(r.filename, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            'Authenticity ${r.authenticity.score} · Completeness ${r.completeness.score}'
                            '${r.summary.peptideDetected != null ? " · ${r.summary.peptideDetected}" : ""}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            ref.read(selectedResultProvider.notifier).set(r);
                            context.go('/results');
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _empty(ColorScheme scheme, String title, String sub) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
}
