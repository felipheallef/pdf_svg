import 'dart:typed_data';

import 'package:pdf_svg/pdf_svg.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

void main() {
  test('renders a simple SVG into PDF bytes', () async {
    const svg = '''
<svg width="24" height="24" viewBox="0 0 24 24"
    xmlns="http://www.w3.org/2000/svg">
  <path d="M 2 2 L 22 2 L 22 22 L 2 22 Z" fill="#ff0000"/>
</svg>
''';

    final si = ScalableImage.fromSvgString(svg, warnF: (_) {});
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(24, 24),
        build: (_) => pw.CustomPaint(
          size: const PdfPoint(24, 24),
          painter: (canvas, size) =>
              si.paint(canvas, document: document.document),
        ),
      ),
    );

    final bytes = await document.save();

    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(0));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
