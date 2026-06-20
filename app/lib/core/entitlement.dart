/// The user's scan entitlement, mirrored from `GET /api/me`. The backend is the
/// source of truth; this is a read-only view used to gate scanning and render
/// the paywall / plan status.
class Entitlement {
  const Entitlement({
    this.email,
    this.plan,
    this.subscriptionActive = false,
    this.credits = 0,
    this.freeScanAvailable = false,
    this.canScan = false,
  });

  final String? email;
  final String? plan; // 'monthly' | 'yearly' | null
  final bool subscriptionActive;
  final int credits;
  final bool freeScanAvailable;
  final bool canScan;

  factory Entitlement.fromJson(Map<String, dynamic> j) {
    final sub = j['subscription'];
    return Entitlement(
      email: j['email'] as String?,
      plan: sub is Map ? sub['plan'] as String? : null,
      subscriptionActive: sub is Map && sub['active'] == true,
      credits: (j['credits'] as num?)?.toInt() ?? 0,
      freeScanAvailable: j['free_scan_available'] == true,
      canScan: j['can_scan'] == true,
    );
  }
}
