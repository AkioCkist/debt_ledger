import 'package:debt_ledger/models/integrity_report.dart';
import 'package:debt_ledger/theme/app_theme.dart';
import 'package:debt_ledger/widgets/integrity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IntegrityReport report({
  List<IntegrityFinding> findings = const [],
  bool hasBaseline = true,
}) {
  return IntegrityReport(
    checkedAt: DateTime(2026, 9, 14, 10, 30),
    hasBaseline: hasBaseline,
    databaseTracksVersions: true,
    findings: findings,
    rowCount: 3,
    clientBalance: 500000,
    changedSinceBaseline: 0,
  );
}

Future<void> pumpCard(
  WidgetTester tester, {
  required IntegrityReport? report,
  bool checking = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: IntegrityCard(
          report: report,
          checking: checking,
          onTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hiện trạng thái đang kiểm tra khi chưa có kết quả', (
    tester,
  ) async {
    await pumpCard(tester, report: null);
    expect(find.text('Đối soát dữ liệu'), findsOneWidget);
    expect(find.textContaining('Đang kiểm tra'), findsOneWidget);
  });

  testWidgets('hiện số bất thường khi có phát hiện nghiêm trọng', (
    tester,
  ) async {
    await pumpCard(
      tester,
      report: report(
        findings: const [
          IntegrityFinding(
            severity: IntegritySeverity.critical,
            code: 'row_payload_changed',
            title: 'Số tiền bị sửa',
            message: 'Giao dịch a đã bị thay đổi ngoài app.',
          ),
        ],
      ),
    );
    expect(find.text('1 bất thường nghiêm trọng'), findsOneWidget);
  });

  testWidgets('hiện trạng thái khớp khi dữ liệu sạch', (tester) async {
    await pumpCard(tester, report: report());
    expect(find.text('Dữ liệu khớp'), findsOneWidget);
    expect(find.textContaining('Không phát hiện thay đổi'), findsOneWidget);
  });

  testWidgets('gọi onTap khi người dùng chạm vào mục', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: IntegrityCard(
            report: report(),
            checking: false,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Đối soát dữ liệu'));
    expect(tapped, isTrue);
  });
}
