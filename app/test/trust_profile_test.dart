import 'package:flutter_test/flutter_test.dart';
import 'package:coa_scanner/features/onboarding/onboarding_models.dart';
import 'package:coa_scanner/features/onboarding/trust_profile.dart';
import 'package:coa_scanner/models/models.dart';

TrustLevel _levelFor(TrustProfile p, String label) =>
    p.signals.firstWhere((s) => s.label == label).level;

void main() {
  group('buildTrustProfile', () {
    test('strong answers → green verdict and green signals', () {
      const a = OnboardingAnswers({
        'vendor': 'telehealth_pharmacy',
        'coa_source': 'third_party',
        'verifiability': 'yes',
        'batch': 'matches',
        'recency': 'under6',
        'test_scope': <String>{'purity', 'ms_identity', 'endotoxin'},
      });
      final p = buildTrustProfile(a);
      expect(p.verdictLevel, TrustLevel.green);
      expect(_levelFor(p, 'COA source'), TrustLevel.green);
      expect(_levelFor(p, 'Verifiable'), TrustLevel.green);
      expect(_levelFor(p, 'Test scope'), TrustLevel.green);
    });

    test('no COA + unverifiable → red verdict', () {
      const a = OnboardingAnswers({
        'vendor': 'overseas_direct',
        'coa_source': 'none',
        'verifiability': 'no',
        'batch': 'different',
        'recency': 'over12',
        'test_scope': <String>{'not_sure'},
      });
      final p = buildTrustProfile(a);
      expect(p.verdictLevel, TrustLevel.red);
      expect(_levelFor(p, 'COA source'), TrustLevel.red);
    });

    test('in-house + single amber → mixed (amber) verdict', () {
      const a = OnboardingAnswers({
        'vendor': 'domestic_reseller',
        'coa_source': 'in_house',
        'verifiability': 'yes',
        'batch': 'matches',
        'recency': 'under6',
        'test_scope': <String>{'purity', 'ms_identity', 'sterility'},
      });
      final p = buildTrustProfile(a);
      expect(p.verdictLevel, TrustLevel.amber); // 2+ ambers (source + coa_source)
    });

    test('just_researching adds no Source signal', () {
      const a = OnboardingAnswers({'vendor': 'just_researching', 'coa_source': 'third_party'});
      final p = buildTrustProfile(a);
      expect(p.signals.any((s) => s.label == 'Source'), isFalse);
    });

    test('purity-only scope is flagged amber, not green', () {
      const a = OnboardingAnswers({'test_scope': <String>{'purity', 'assay'}});
      final p = buildTrustProfile(a);
      expect(_levelFor(p, 'Test scope'), TrustLevel.amber);
    });
  });

  group('reconciliation with scan', () {
    ScanResult scanWith(Map<String, dynamic> hardChecks, {List<Map<String, dynamic>> checklist = const []}) {
      return ScanResult.fromJson({
        'authenticity': {'score': 80, 'label': 'verify_recommended', 'copy': ''},
        'completeness': {'score': 60, 'label': 'partial_report', 'copy': '', 'checklist': checklist},
        'summary': {},
        'hard_checks': hardChecks,
        'rule_results': [],
        'features': {},
        'llm': {'enabled': false},
      });
    }

    test('claimed third-party but scan says in-house → COA source red', () {
      const a = OnboardingAnswers({'coa_source': 'third_party'});
      final scan = scanWith({'doc_type': {'status': 'manufacturer_qc'}});
      final p = buildTrustProfile(a, scan: scan);
      expect(_levelFor(p, 'COA source'), TrustLevel.red);
    });

    test('claimed verifiable but scan found no verification path → Verifiable red', () {
      const a = OnboardingAnswers({'verifiability': 'yes'});
      final scan = scanWith({'verifiability': {'status': 'no_verification_path'}});
      final p = buildTrustProfile(a, scan: scan);
      expect(_levelFor(p, 'Verifiable'), TrustLevel.red);
    });

    test('scan verification path OVERRIDES a "no" answer → Verifiable green (the bug)', () {
      const a = OnboardingAnswers({'verifiability': 'no'});
      final scan = scanWith({'verifiability': {'status': 'verifiable'}});
      final p = buildTrustProfile(a, scan: scan);
      expect(_levelFor(p, 'Verifiable'), TrustLevel.green);
    });

    test('Janoshik key pending also counts as verifiable', () {
      const a = OnboardingAnswers({'verifiability': 'unsure'});
      final scan = scanWith({
        'verifiability': {'status': 'deferred_to_janoshik'},
        'janoshik': {'status': 'pending_user_verification'},
      });
      final p = buildTrustProfile(a, scan: scan);
      expect(_levelFor(p, 'Verifiable'), TrustLevel.green);
    });

    test('claimed MS identity but checklist shows it absent → amber over-claim flag', () {
      const a = OnboardingAnswers({'test_scope': <String>{'ms_identity'}});
      final scan = scanWith({}, checklist: [
        {'section': 'identity', 'label': 'Identity', 'present': false}
      ]);
      final p = buildTrustProfile(a, scan: scan);
      expect(p.signals.any((s) => s.label == 'Tests not found' && s.level == TrustLevel.amber), isTrue);
    });

    test('no red signals when answers agree with scan', () {
      const a = OnboardingAnswers({'coa_source': 'third_party', 'verifiability': 'yes'});
      final scan = scanWith({
        'doc_type': {'status': 'third_party_lab'},
        'verifiability': {'status': 'verifiable'},
      });
      final p = buildTrustProfile(a, scan: scan);
      expect(p.signals.any((s) => s.level == TrustLevel.red), isFalse);
    });
  });
}
