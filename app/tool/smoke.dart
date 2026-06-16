// Ad-hoc end-to-end check of the app's data layer against a running backend.
//
//   cd backend && uvicorn app.main:app   # http://localhost:8000
//   cd app && dart run tool/smoke.dart [API_BASE_URL]
//
// Scans a real COA, a fake, and a blank file, and prints how the frontend
// models parsed each response. Not part of `flutter test` (needs a live
// backend + filesystem access to the sample COAs).
import 'dart:io';

import 'package:coa_scanner/data/http_api_client.dart';
import 'package:coa_scanner/models/models.dart';

const _repoRoot = '..';

Future<void> main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args.first : 'http://localhost:8000';
  final api = HttpApiClient(baseUrl: baseUrl);

  stdout.writeln('Backend: $baseUrl');
  stdout.writeln('Health: ${await api.health() ? "OK" : "UNREACHABLE"}\n');

  final samples = <String>[
    '$_repoRoot/COAs/Janoshik_Tests/#100491_BPC-157_10mg_+_TB_500_10mg.pdf',
    '$_repoRoot/FAKE/Fake1.png',
  ];

  for (final path in samples) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('SKIP (missing): $path\n');
      continue;
    }
    final bytes = await file.readAsBytes();
    stdout.writeln('── ${path.split('/').last} (${bytes.length} bytes)');
    try {
      final outcome = await api.scan(bytes: bytes, filename: path.split('/').last);
      switch (outcome) {
        case ScanSuccess(:final result):
          _printResult(result);
        case ScanNotACoaOutcome(:final info):
          stdout.writeln('  not-a-COA: ${info.message} (${info.ocrChars} chars)');
      }
    } on ApiException catch (e) {
      stdout.writeln('  ApiException ${e.statusCode}: ${e.message}');
    }
    stdout.writeln('');
  }
  exit(0);
}

void _printResult(ScanResult r) {
  stdout.writeln('  authenticity: ${r.authenticity.score} (${r.authenticity.label})');
  stdout.writeln('  completeness: ${r.completeness.score} (${r.completeness.label})');
  stdout.writeln('  peptide: ${r.summary.peptideDetected} · input: ${r.inputType}');
  final janoshik = r.hardChecks.byName('janoshik');
  if (janoshik != null) {
    stdout.writeln('  janoshik: ${janoshik.status}'
        '${janoshik.verificationUrl != null ? " → ${janoshik.verificationUrl}" : ""}');
  }
  final lab = r.hardChecks.byName('known_lab');
  if (lab != null) stdout.writeln('  known_lab: ${lab.status} (${lab.labName ?? "-"}, trust ${lab.trust ?? "-"})');
  stdout.writeln('  findings shown: ${r.hardChecks.findings.length} · rule_results: ${r.ruleResults.length}'
      ' · llm.didRun: ${r.llm.didRun}');
  // Sanity: copy is verbatim from backend, never the raw label.
  assert(r.authenticity.copy.isNotEmpty, 'authenticity.copy should be populated');
}
