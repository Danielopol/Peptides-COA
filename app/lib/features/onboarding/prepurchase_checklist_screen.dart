import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/disclaimer.dart';
import '../shared/widgets/page_body.dart';

/// Static "what to demand before you buy" checklist (RUO framing), grounded in
/// the Articles vendor-selection & COA guides. For the "just researching" path.
class PrePurchaseChecklistScreen extends StatelessWidget {
  const PrePurchaseChecklistScreen({super.key});

  static const List<(String, String)> _items = [
    ('Third-party COA, not in-house',
        'An independent, accredited lab tested it — not the seller. Ask: which lab produced this report?'),
    ('A named, real, accredited lab',
        'Full lab name + contact; look for ISO/IEC 17025 (or A2LA/NVLAP). You should be able to find the lab independently.'),
    ('A way to verify it yourself',
        'A QR code, verification key, or lookup portal on the lab’s own site. No verification path = treat as unverified.'),
    ('Batch-matched & recent',
        'The COA’s lot matches the vial, and testing is recent (ideally < 6 months; be wary past 12).'),
    ('HPLC purity + MS identity',
        'Purity (HPLC) AND identity by mass spec — purity alone doesn’t prove it’s the right compound.'),
    ('Contaminant testing for sensitive work',
        'Heavy metals, endotoxin, sterility — rarely on grey-market COAs, but what real safety depends on.'),
    ('A real vendor presence',
        'Storefront, physical address, responsive support. Avoid DM/WhatsApp-only sellers and crypto-only payment (irreversible).'),
    ('Plan to verify or test',
        'Confirm the COA at the lab; for anything important, budget for an independent or group test of your own vial.'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/onboarding/summary')),
        title: const Text('Before you buy'),
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'Demand these before sourcing a research compound. The more that are missing, the higher the risk.',
              style: TextStyle(height: 1.45, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ..._items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 20, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(it.$2, style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Verify a COA now'),
              onPressed: () => context.go('/'),
            ),
            const SizedBox(height: 20),
            const DisclaimerBanner(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
