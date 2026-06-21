import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/page_body.dart';

/// Operator / contact details surfaced in the legal docs.
const String kServiceName = 'PeptidesTrust';
const String kOperatorName = 'Valentin Daniel Marin';
const String kOperatorLocation = 'Romania (EU)';
const String kContactEmail = 'valentin.marin83@gmail.com';
const String kContactPhone = '+40 728 083 312';
const String kLastUpdated = 'June 21, 2026';

class LegalDoc {
  const LegalDoc(this.title, this.sections);
  final String title;
  final List<(String, String)> sections;
}

/// Small inline underlined link to a legal page (pushes so the back arrow
/// returns the user to where they were).
Widget legalLink(BuildContext context, String label, String route, Color color) {
  return InkWell(
    onTap: () => context.push(route),
    child: Text(label,
        style: TextStyle(fontSize: 11.5, color: color, decoration: TextDecoration.underline)),
  );
}

/// Renders one of the legal documents by key: 'terms' | 'privacy' | 'refund'.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.docKey});

  final String docKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final doc = _docs[docKey] ?? _docs['terms']!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(doc.title),
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('Last updated: $kLastUpdated',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (final (heading, body) in doc.sections) ...[
              Text(heading,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(body, style: TextStyle(fontSize: 13.5, height: 1.5, color: scheme.onSurface)),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

final Map<String, LegalDoc> _docs = {
  'terms': const LegalDoc('Terms of Service', [
    (
      '1. About the Service',
      '$kServiceName (the “Service”) is operated by $kOperatorName, an individual based '
          'in $kOperatorLocation (the “Operator”, “we”, “us”). The Service is a web-based '
          'software tool that analyses uploaded Certificates of Analysis (COAs) for '
          'research-use-only laboratory peptides and returns an automated authenticity and '
          'completeness assessment. It is available to users worldwide. Contact: '
          '$kContactEmail, $kContactPhone. By creating an account or using the Service you '
          'agree to these Terms.'
    ),
    (
      '2. Informational use — no guarantee',
      'The Service provides automated, probabilistic analysis for informational '
          'purposes only. It does NOT certify, guarantee, or prove the authenticity, '
          'purity, identity, quality, safety, or legality of any document, product, or '
          'substance, and is not a substitute for accredited laboratory testing or '
          'professional advice. Results may be incomplete or incorrect. Any decision you '
          'make based on the Service is at your own risk.'
    ),
    (
      '3. Research-use-only — no medical advice',
      'All content relates to research-use-only materials. Nothing in the Service is '
          'medical, health, veterinary, legal, or other professional advice, and nothing '
          'encourages or facilitates the purchase, sale, or use of any substance in '
          'humans or animals. You are solely responsible for complying with all laws and '
          'regulations applicable to you.'
    ),
    (
      '4. Eligibility & accounts',
      'You must be at least 18 years old and able to form a binding contract. You are '
          'responsible for the accuracy of your account information and for all activity '
          'under your account and credentials. Notify us promptly of any unauthorised use.'
    ),
    (
      '5. Acceptable use',
      'You agree not to: use the Service unlawfully; upload content you do not have the '
          'right to submit; attempt to disrupt, overload, reverse-engineer, or gain '
          'unauthorised access to the Service; scrape or use it via unauthorised automated '
          'means; or resell or sublicense access without our permission.'
    ),
    (
      '6. Plans, payments & billing',
      'The free tier includes a limited number of scans per calendar month. Paid options '
          'include prepaid scan-credit packs (one-time purchases) and auto-renewing '
          'monthly or annual subscriptions. Prices are shown at checkout. Payments are '
          'processed by Stripe; we do not store your full card details. Subscriptions '
          'renew automatically until cancelled; you may cancel at any time and retain '
          'access until the end of the paid period. See our Refund Policy.'
    ),
    (
      '7. Intellectual property',
      'The Service, including its software, design, and content, is owned by us or our '
          'licensors and protected by law. We grant you a limited, revocable, '
          'non-transferable, non-exclusive licence to use the Service for its intended '
          'purpose. You retain ownership of documents you upload and grant us a licence to '
          'process them as needed to provide the Service.'
    ),
    (
      '8. Disclaimers',
      'To the maximum extent permitted by law, the Service is provided “as is” and “as '
          'available”, without warranties of any kind, whether express or implied, '
          'including merchantability, fitness for a particular purpose, accuracy, or '
          'non-infringement.'
    ),
    (
      '9. Limitation of liability',
      'To the maximum extent permitted by law, we are not liable for any indirect, '
          'incidental, special, or consequential damages, or for any loss arising from '
          'decisions made in reliance on the Service. Our total aggregate liability is '
          'limited to the amount you paid us in the 12 months before the event giving rise '
          'to the claim. Nothing in these Terms limits liability that cannot be limited '
          'under applicable law, including mandatory consumer rights.'
    ),
    (
      '10. Changes & termination',
      'We may modify, suspend, or discontinue the Service or these Terms at any time; we '
          'will give reasonable notice of material changes. We may suspend or terminate '
          'accounts that breach these Terms.'
    ),
    (
      '11. Governing law',
      'These Terms are governed by the laws of Romania and the European Union. Disputes '
          'are subject to the competent courts of Romania, without prejudice to any '
          'mandatory consumer-protection rights you have where you live.'
    ),
    (
      '12. Contact',
      'Questions about these Terms: $kContactEmail / $kContactPhone.'
    ),
  ]),
  'privacy': const LegalDoc('Privacy Policy', [
    (
      '1. Who we are',
      'The Service ($kServiceName) is operated by $kOperatorName, an individual based in '
          '$kOperatorLocation, who is the controller of personal data processed through '
          'the Service. Contact: $kContactEmail, $kContactPhone. We serve users worldwide: '
          'if you are in the EU/EEA the GDPR applies, and we extend the same core '
          'protections to users elsewhere. This policy explains what we collect, why, and '
          'your rights.'
    ),
    (
      '2. Data we collect',
      '• Account data: your email address and authentication identifiers (via Supabase; '
          'if you use Google sign-in, your Google email and basic profile).\n'
          '• Uploaded documents: the COA files you submit and the analysis results we '
          'generate.\n'
          '• Usage & technical data: IP address, device/browser information, and logs.\n'
          '• Payment data: handled by Stripe. We receive limited transaction metadata '
          '(e.g. plan, status) but not your full card number.'
    ),
    (
      '3. How we use your data',
      'To provide and operate the Service (run scans, manage your account and '
          'entitlements, keep your scan history), to process payments, to maintain '
          'security and prevent abuse, to improve the Service, and to comply with legal '
          'obligations. Our legal bases include performance of a contract, legitimate '
          'interests, consent, and legal compliance.'
    ),
    (
      '4. Processing of uploaded documents',
      'COA files you upload are processed by our backend and by a third-party AI vision '
          'provider (Google Gemini) to extract text and assess the document. Please do not '
          'upload personal or confidential information that you do not want processed for '
          'this purpose.'
    ),
    (
      '5. Service providers (processors)',
      'We share data with providers who help us run the Service: Supabase (authentication '
          'and database, EU region), Railway (backend hosting), Vercel (frontend hosting '
          'and privacy-friendly analytics), Stripe (payment processing), and Google '
          '(Gemini AI processing; Google sign-in). Each processes data under its own terms '
          'and privacy policy.'
    ),
    (
      '6. International transfers',
      'Some providers may process data outside the European Economic Area. Where they do, '
          'appropriate safeguards (such as Standard Contractual Clauses) apply.'
    ),
    (
      '7. Retention',
      'We keep your account data and scan history while your account is active. We delete '
          'your data on account closure or on request, except where we must retain certain '
          'records (e.g. payment records) to comply with the law.'
    ),
    (
      '8. Your rights (GDPR)',
      'You have the right to access, rectify, erase, restrict, and port your data, to '
          'object to certain processing, and to withdraw consent at any time. To exercise '
          'these rights, contact $kContactEmail. You may also lodge a complaint with your '
          'supervisory authority — in Romania, the ANSPDCP.'
    ),
    (
      '9. Cookies & local storage',
      'We use essential local/session storage to keep you signed in and to remember your '
          'onboarding answers, plus privacy-friendly analytics to understand aggregate '
          'usage. We do not use advertising trackers.'
    ),
    (
      '10. Security',
      'We use reasonable technical and organisational measures to protect your data, '
          'including access controls and row-level security on your records. No method of '
          'transmission or storage is completely secure.'
    ),
    (
      '11. Children',
      'The Service is not directed to anyone under 18, and we do not knowingly collect '
          'their data.'
    ),
    (
      '12. Changes & contact',
      'We may update this policy and will note the “last updated” date above. Questions: '
          '$kContactEmail / $kContactPhone.'
    ),
  ]),
  'refund': const LegalDoc('Refund & Cancellation Policy', [
    (
      '1. Overview',
      'We offer prepaid scan-credit packs (one-time purchases) and auto-renewing monthly '
          'and annual subscriptions. This policy explains cancellations and refunds. '
          'Payments are processed by Stripe.'
    ),
    (
      '2. Subscriptions',
      'Subscriptions renew automatically until you cancel. You can cancel at any time; '
          'cancellation stops future renewals and you keep access until the end of the '
          'current paid period. We do not generally refund the unused portion of a period '
          'already started, except where required by law.'
    ),
    (
      '3. Scan-credit packs',
      'Scan credits are prepaid. Unused credits may be refunded within 14 days of '
          'purchase on request. Credits that have already been used (i.e. a scan has been '
          'completed) are non-refundable. A scan that fails or is rejected as not a valid '
          'COA does not consume a credit.'
    ),
    (
      '4. EU right of withdrawal',
      'As a consumer in the EU you generally have a 14-day right to withdraw from a '
          'purchase of digital services. By starting to use a paid scan or subscription '
          'immediately, you expressly request immediate performance and acknowledge that '
          'you lose the right of withdrawal for the part of the service already performed '
          '(e.g. credits already used). Unused or not-yet-started portions may still be '
          'withdrawn within 14 days.'
    ),
    (
      '5. Billing errors',
      'If you are charged in error (for example a duplicate charge), contact us and we '
          'will investigate and correct it promptly.'
    ),
    (
      '6. How to request a refund',
      'Email $kContactEmail from the address on your account, including the transaction '
          'date and amount. We aim to respond within a few business days.'
    ),
  ]),
};
