import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/onboarding_controller.dart' show sharedPrefsProvider;

/// SIMULATED payments layer — no real money moves anywhere. This models the
/// intended monetisation so the UX can be exercised end-to-end before wiring a
/// real provider (Stripe/RevenueCat/...):
///
///   free  — onboarding trust guide, trust profile, achievements, history
///   paid  — the scan itself ("check a COA"), via one of three plans:
///           pay-per-scan $2 · monthly $7 · yearly $50 (orientative pricing)
///
/// Pay-per-scan grants credits; a credit is consumed only when a scan actually
/// completes (failed uploads / not-a-COA don't burn it). Subscriptions are
/// unlimited until their simulated expiry date.
enum Plan { none, payPerScan, monthly, yearly }

class Pricing {
  const Pricing._();
  static const double perScanUsd = 2;
  static const double monthlyUsd = 7;
  static const double yearlyUsd = 50;
}

class PaymentsState {
  const PaymentsState({
    this.plan = Plan.none,
    this.credits = 0,
    this.expiry,
  });

  final Plan plan;
  final int credits; // pay-per-scan credits left
  final DateTime? expiry; // subscription end (simulated)

  bool get subscriptionActive =>
      (plan == Plan.monthly || plan == Plan.yearly) &&
      expiry != null &&
      DateTime.now().isBefore(expiry!);

  /// Whether pressing "check a COA" may proceed without hitting the paywall.
  bool get canScan => subscriptionActive || credits > 0;

  PaymentsState copyWith({Plan? plan, int? credits, DateTime? expiry}) =>
      PaymentsState(
        plan: plan ?? this.plan,
        credits: credits ?? this.credits,
        expiry: expiry ?? this.expiry,
      );
}

class PaymentsController extends Notifier<PaymentsState> {
  static const _kPlan = 'pay_plan';
  static const _kCredits = 'pay_credits';
  static const _kExpiry = 'pay_expiry_ms';

  @override
  PaymentsState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final expiryMs = prefs.getInt(_kExpiry);
    return PaymentsState(
      plan: Plan.values.asNameMap()[prefs.getString(_kPlan)] ?? Plan.none,
      credits: prefs.getInt(_kCredits) ?? 0,
      expiry: expiryMs == null ? null : DateTime.fromMillisecondsSinceEpoch(expiryMs),
    );
  }

  /// Simulated $2 checkout → +1 scan credit (credits stack).
  void buyScanCredit() {
    state = state.copyWith(plan: Plan.payPerScan, credits: state.credits + 1);
    _persist();
  }

  /// Simulated subscription checkout. Monthly = +30 days, yearly = +365 days.
  void subscribe(Plan plan) {
    assert(plan == Plan.monthly || plan == Plan.yearly);
    final days = plan == Plan.monthly ? 30 : 365;
    state = state.copyWith(
      plan: plan,
      expiry: DateTime.now().add(Duration(days: days)),
    );
    _persist();
  }

  /// Burn one credit after a completed scan (subscriptions are unlimited).
  void consumeCredit() {
    if (state.subscriptionActive) return;
    if (state.credits <= 0) return;
    state = state.copyWith(credits: state.credits - 1);
    _persist();
  }

  /// Reset the simulation (testing aid on the paywall screen).
  void clear() {
    state = const PaymentsState();
    final prefs = ref.read(sharedPrefsProvider);
    prefs.remove(_kPlan);
    prefs.remove(_kCredits);
    prefs.remove(_kExpiry);
  }

  void _persist() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(_kPlan, state.plan.name);
    prefs.setInt(_kCredits, state.credits);
    final e = state.expiry;
    if (e != null) prefs.setInt(_kExpiry, e.millisecondsSinceEpoch);
  }
}

final paymentsProvider =
    NotifierProvider<PaymentsController, PaymentsState>(PaymentsController.new);
