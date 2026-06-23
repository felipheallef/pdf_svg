/*
Copyright (c) 2021-2025, William Foote

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

  * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/

///
/// PDF-backed rendering primitives used by the forked renderer.
///
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:vector_math/vector_math_64.dart';

import 'common_noui.dart';
import 'path_noui.dart';

export 'package:meta/meta.dart' show immutable, protected, mustCallSuper;
export 'package:pdf/pdf.dart'
    show
        PdfDocument,
        PdfGraphics,
        PdfPageFormat,
        PdfColor,
        PdfColors,
        PdfGraphicState,
        PdfSoftMask,
        PdfBlendMode,
        PdfLineCap,
        PdfLineJoin,
        PdfImage;

@immutable
class Color {
  final int value;

  const Color(this.value);

  const Color.fromARGB(int a, int r, int g, int b)
    : value = ((a & 0xff) << 24) |
          ((r & 0xff) << 16) |
          ((g & 0xff) << 8) |
          (b & 0xff);

  double get a => ((value >> 24) & 0xff) / 255.0;
  double get r => ((value >> 16) & 0xff) / 255.0;
  double get g => ((value >> 8) & 0xff) / 255.0;
  double get b => (value & 0xff) / 255.0;

  pdf.PdfColor get pdfColor => pdf.PdfColor(r, g, b, a);

  @override
  bool operator ==(Object other) => other is Color && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Color(0x${value.toRadixString(16).padLeft(8, '0')})';
}

class Colors {
  static const black = Color(0xff000000);
  static const white = Color(0xffffffff);
}

@immutable
class Offset {
  final double dx;
  final double dy;

  const Offset(this.dx, this.dy);
}

@immutable
class Size {
  final double width;
  final double height;

  const Size(this.width, this.height);
}

@immutable
class Radius {
  final double x;
  final double y;

  const Radius.elliptical(this.x, this.y);
}

@immutable
class Rect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const Rect.fromLTRB(this.left, this.top, this.right, this.bottom);

  const Rect.fromLTWH(double left, double top, double width, double height)
    : this.fromLTRB(left, top, left + width, top + height);

  static const zero = Rect.fromLTRB(0, 0, 0, 0);

  double get width => right - left;
  double get height => bottom - top;

  bool overlaps(Rect other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;

  Rect deflate(double delta) =>
      Rect.fromLTRB(left + delta, top + delta, right - delta, bottom - delta);

  Rect expandToInclude(Rect other) => Rect.fromLTRB(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  Rect intersect(Rect other) => Rect.fromLTRB(
    math.max(left, other.left),
    math.max(top, other.top),
    math.min(right, other.right),
    math.min(bottom, other.bottom),
  );

  pdf.PdfRect get pdfRect => pdf.PdfRect(left, top, width, height);

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Rect.fromLTRB($left, $top, $right, $bottom)';
}

enum BlendMode {
  srcOver,
  srcIn,
  srcATop,
  multiply,
  screen,
  plus,
  clear,
  color,
  colorBurn,
  colorDodge,
  darken,
  difference,
  dst,
  dstATop,
  dstIn,
  dstOut,
  dstOver,
  exclusion,
  hardLight,
  hue,
  lighten,
  luminosity,
  modulate,
  overlay,
  saturation,
  softLight,
  src,
  srcOut,
  xor,
}

enum StrokeJoin { miter, round, bevel }

enum StrokeCap { butt, round, square }

enum PathFillType { evenOdd, nonZero }

enum PaintingStyle { fill, stroke }

enum TileMode { clamp, mirror, repeated }

class ColorFilter {
  const ColorFilter.matrix(List<double> matrix);
}

class Paint {
  Color color = Colors.black;
  PaintingStyle style = PaintingStyle.fill;
  double strokeWidth = 1;
  StrokeCap strokeCap = StrokeCap.butt;
  StrokeJoin strokeJoin = StrokeJoin.miter;
  double strokeMiterLimit = 4;
  BlendMode? blendMode;
  Object? shader;
  ColorFilter? colorFilter;
}

class Gradient {
  static Object linear(
    Offset from,
    Offset to,
    List<Color> colors,
    List<double> stops,
    TileMode tileMode, [
    Float64List? matrix4,
  ]) => _LinearGradientData(from, to, colors, stops, matrix4);

  static Object radial(
    Offset center,
    double radius,
    List<Color> colors,
    List<double> stops,
    TileMode tileMode, [
    Float64List? matrix4,
    Offset? focal,
  ]) => _RadialGradientData(center, radius, colors, stops, matrix4, focal);

  static Object sweep(
    Offset center,
    List<Color> colors,
    List<double> stops,
    TileMode tileMode,
    double startAngle,
    double endAngle, [
    Float64List? matrix4,
  ]) => _SweepGradientData(colors);
}

class _LinearGradientData {
  final Offset from;
  final Offset to;
  final List<Color> colors;
  final List<double> stops;
  final Float64List? matrix4;

  _LinearGradientData(this.from, this.to, this.colors, this.stops, this.matrix4);
}

class _RadialGradientData {
  final Offset center;
  final double radius;
  final List<Color> colors;
  final List<double> stops;
  final Float64List? matrix4;
  final Offset? focal;

  _RadialGradientData(
    this.center,
    this.radius,
    this.colors,
    this.stops,
    this.matrix4,
    this.focal,
  );
}

class _SweepGradientData {
  final List<Color> colors;

  _SweepGradientData(this.colors);
}

class Path {
  final StringBuffer _data = StringBuffer();
  Rect? _bounds;

  Path();

  Path.from(Path other) {
    _data.write(other.data);
    _bounds = other._bounds;
    fillType = other.fillType;
  }

  PathFillType fillType = PathFillType.nonZero;

  String get data => _data.toString();

  void moveTo(double x, double y) {
    _data.write('M $x $y ');
    _include(x, y);
  }

  void lineTo(double x, double y) {
    _data.write('L $x $y ');
    _include(x, y);
  }

  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    _data.write('C $x1 $y1 $x2 $y2 $x3 $y3 ');
    _include(x1, y1);
    _include(x2, y2);
    _include(x3, y3);
  }

  void quadraticBezierTo(double x1, double y1, double x2, double y2) {
    _data.write('Q $x1 $y1 $x2 $y2 ');
    _include(x1, y1);
    _include(x2, y2);
  }

  void arcToPoint(
    Offset arcEnd, {
    required Radius radius,
    required double rotation,
    required bool largeArc,
    required bool clockwise,
  }) {
    _data.write(
      'A ${radius.x} ${radius.y} $rotation ${largeArc ? 1 : 0} ${clockwise ? 1 : 0} ${arcEnd.dx} ${arcEnd.dy} ',
    );
    _include(arcEnd.dx, arcEnd.dy);
  }

  void addOval(Rect rect) {
    final cx = rect.left + rect.width / 2;
    final cy = rect.top + rect.height / 2;
    moveTo(cx + rect.width / 2, cy);
    arcToPoint(
      Offset(cx - rect.width / 2, cy),
      radius: Radius.elliptical(rect.width / 2, rect.height / 2),
      rotation: 0,
      largeArc: false,
      clockwise: true,
    );
    arcToPoint(
      Offset(cx + rect.width / 2, cy),
      radius: Radius.elliptical(rect.width / 2, rect.height / 2),
      rotation: 0,
      largeArc: false,
      clockwise: true,
    );
    close();
  }

  void close() {
    _data.write('Z ');
  }

  Rect getBounds() {
    if (_bounds != null) {
      return _bounds!;
    }
    if (data.trim().isEmpty) {
      return Rect.zero;
    }
    final box = pdf.PdfGraphics.shapeBoundingBox(data);
    return Rect.fromLTWH(box.left, box.bottom, box.width, box.height);
  }

  Iterable<PathMetric> computeMetrics() => const <PathMetric>[];

  void _include(double x, double y) {
    final b = _bounds;
    if (b == null) {
      _bounds = Rect.fromLTWH(x, y, 0, 0);
    } else {
      _bounds = Rect.fromLTRB(
        math.min(b.left, x),
        math.min(b.top, y),
        math.max(b.right, x),
        math.max(b.bottom, y),
      );
    }
  }
}

class PathMetric {
  double get length => 0;

  Path extractPath(double start, double end) => Path();
}

class Canvas {
  final pdf.PdfGraphics graphics;
  final pdf.PdfDocument document;

  Canvas(this.graphics, this.document);

  void save() => graphics.saveContext();

  void restore() => graphics.restoreContext();

  void saveLayer(Rect? bounds, Paint paint) {
    save();
    final bm = paint.blendMode?.pdfBlendMode;
    if (bm != null) {
      graphics.setGraphicState(pdf.PdfGraphicState(blendMode: bm));
    }
  }

  void translate(double dx, double dy) {
    final m = Matrix4.identity()..translateByDouble(dx, dy, 0, 1);
    graphics.setTransform(m);
  }

  void scale(double sx, [double? sy]) {
    final m = Matrix4.identity()..scaleByDouble(sx, sy ?? sx, 1, 1);
    graphics.setTransform(m);
  }

  void transform(Float64List storage) {
    graphics.setTransform(Matrix4.fromFloat64List(storage));
  }

  void clipRect(Rect rect) {
    graphics.drawRect(rect.left, rect.top, rect.width, rect.height);
    graphics.clipPath();
  }

  void clipPath(Path path) {
    graphics.drawShape(path.data);
    graphics.clipPath(evenOdd: path.fillType == PathFillType.evenOdd);
  }

  void drawPath(Path path, Paint paint) {
    graphics.drawShape(path.data);
    _applyPaint(paint, stroke: paint.style == PaintingStyle.stroke);
    if (paint.style == PaintingStyle.stroke) {
      graphics.strokePath();
    } else {
      graphics.fillPath(evenOdd: path.fillType == PathFillType.evenOdd);
    }
  }

  void drawRect(Rect rect, Paint paint) {
    graphics.drawRect(rect.left, rect.top, rect.width, rect.height);
    _applyPaint(paint, stroke: paint.style == PaintingStyle.stroke);
    if (paint.style == PaintingStyle.stroke) {
      graphics.strokePath();
    } else {
      graphics.fillPath();
    }
  }

  void drawColor(Color color, BlendMode mode) {
    graphics.setFillColor(color.pdfColor);
  }

  void drawImageRect(Image image, Rect src, Rect dest, Paint paint) {
    graphics.drawImage(image.image, dest.left, dest.top, dest.width, dest.height);
  }

  void _applyPaint(Paint paint, {required bool stroke}) {
    final bm = paint.blendMode?.pdfBlendMode;
    if (bm != null) {
      graphics.setGraphicState(pdf.PdfGraphicState(blendMode: bm));
    }
    final shader = paint.shader;
    if (shader != null) {
      final pattern = _patternFor(shader);
      if (pattern != null) {
        if (stroke) {
          _applyStrokeState(paint);
          graphics.setStrokePattern(pattern);
        } else {
          graphics.setFillPattern(pattern);
        }
        return;
      }
    }
    if (stroke) {
      _applyStrokeState(paint);
      graphics.setStrokeColor(paint.color.pdfColor);
    } else {
      graphics.setFillColor(paint.color.pdfColor);
    }
  }

  void _applyStrokeState(Paint paint) {
    graphics
      ..setLineWidth(paint.strokeWidth)
      ..setLineCap(paint.strokeCap.pdfLineCap)
      ..setLineJoin(paint.strokeJoin.pdfLineJoin)
      ..setMiterLimit(paint.strokeMiterLimit);
  }

  pdf.PdfShadingPattern? _patternFor(Object shader) {
    if (shader is _LinearGradientData) {
      return pdf.PdfShadingPattern(
        document,
        shading: pdf.PdfShading(
          document,
          shadingType: pdf.PdfShadingType.axial,
          function: pdf.PdfBaseFunction.colorsAndStops(
            document,
            shader.colors.map((c) => c.pdfColor).toList(growable: false),
            shader.stops,
          ),
          start: pdf.PdfPoint(shader.from.dx, shader.from.dy),
          end: pdf.PdfPoint(shader.to.dx, shader.to.dy),
          extendStart: true,
          extendEnd: true,
        ),
        matrix: shader.matrix4 == null
            ? null
            : Matrix4.fromFloat64List(shader.matrix4!),
      );
    }
    if (shader is _RadialGradientData) {
      final focal = shader.focal ?? shader.center;
      return pdf.PdfShadingPattern(
        document,
        shading: pdf.PdfShading(
          document,
          shadingType: pdf.PdfShadingType.radial,
          function: pdf.PdfBaseFunction.colorsAndStops(
            document,
            shader.colors.map((c) => c.pdfColor).toList(growable: false),
            shader.stops,
          ),
          start: pdf.PdfPoint(focal.dx, focal.dy),
          end: pdf.PdfPoint(shader.center.dx, shader.center.dy),
          radius0: 0,
          radius1: shader.radius,
          extendStart: true,
          extendEnd: true,
        ),
        matrix: shader.matrix4 == null
            ? null
            : Matrix4.fromFloat64List(shader.matrix4!),
      );
    }
    if (shader is _SweepGradientData && shader.colors.isNotEmpty) {
      return null;
    }
    return null;
  }
}

class Image {
  final pdf.PdfImage image;

  Image(this.image);

  int get width => image.width;
  int get height => image.height;
}

extension StrokeCapPdf on StrokeCap {
  pdf.PdfLineCap get pdfLineCap {
    switch (this) {
      case StrokeCap.butt:
        return pdf.PdfLineCap.butt;
      case StrokeCap.round:
        return pdf.PdfLineCap.round;
      case StrokeCap.square:
        return pdf.PdfLineCap.square;
    }
  }
}

extension StrokeJoinPdf on StrokeJoin {
  pdf.PdfLineJoin get pdfLineJoin {
    switch (this) {
      case StrokeJoin.miter:
        return pdf.PdfLineJoin.miter;
      case StrokeJoin.round:
        return pdf.PdfLineJoin.round;
      case StrokeJoin.bevel:
        return pdf.PdfLineJoin.bevel;
    }
  }
}

extension BlendModePdf on BlendMode {
  pdf.PdfBlendMode? get pdfBlendMode {
    switch (this) {
      case BlendMode.multiply:
        return pdf.PdfBlendMode.multiply;
      case BlendMode.screen:
        return pdf.PdfBlendMode.screen;
      case BlendMode.overlay:
        return pdf.PdfBlendMode.overlay;
      case BlendMode.darken:
        return pdf.PdfBlendMode.darken;
      case BlendMode.lighten:
        return pdf.PdfBlendMode.lighten;
      case BlendMode.colorDodge:
        return pdf.PdfBlendMode.colorDodge;
      case BlendMode.colorBurn:
        return pdf.PdfBlendMode.colorBurn;
      case BlendMode.hardLight:
        return pdf.PdfBlendMode.hardLight;
      case BlendMode.softLight:
        return pdf.PdfBlendMode.softLight;
      case BlendMode.difference:
        return pdf.PdfBlendMode.difference;
      case BlendMode.exclusion:
        return pdf.PdfBlendMode.exclusion;
      case BlendMode.hue:
        return pdf.PdfBlendMode.hue;
      case BlendMode.saturation:
        return pdf.PdfBlendMode.saturation;
      case BlendMode.color:
        return pdf.PdfBlendMode.color;
      case BlendMode.luminosity:
        return pdf.PdfBlendMode.luminosity;
      case BlendMode.srcOver:
      case BlendMode.srcIn:
      case BlendMode.srcATop:
      case BlendMode.plus:
      case BlendMode.clear:
      case BlendMode.dst:
      case BlendMode.dstATop:
      case BlendMode.dstIn:
      case BlendMode.dstOut:
      case BlendMode.dstOver:
      case BlendMode.modulate:
      case BlendMode.src:
      case BlendMode.srcOut:
      case BlendMode.xor:
        return null;
    }
  }
}

class SiPaintContext {
  final Canvas canvas;

  SiPaintContext(pdf.PdfGraphics graphics, pdf.PdfDocument document)
    : canvas = Canvas(graphics, document);
}

class PdfCanvas extends Canvas {
  PdfCanvas(super.graphics, super.document);
}

class TextPainter {
  final TextSpan text;
  final TextDirection textDirection;
  double width = 0;
  double height = 0;

  TextPainter({required this.text, required this.textDirection});

  void layout() {
    final size = text.style?.fontSize ?? 16;
    width = (text.text ?? '').length * size * 0.6;
    height = size;
  }

  double computeDistanceToActualBaseline(TextBaseline baseline) => height * 0.8;

  void paint(Canvas canvas, Offset offset) {
    final fontSize = text.style?.fontSize ?? 16;
    canvas.graphics
      ..setFillColor((text.style?.foreground?.color ?? Colors.black).pdfColor)
      ..drawString(
        pdf.PdfFont.helvetica(canvas.document),
        fontSize,
        text.text ?? '',
        offset.dx,
        offset.dy + fontSize,
      );
  }
}

class TextSpan {
  final TextStyle? style;
  final String? text;

  TextSpan({this.style, this.text});
}

class TextStyle {
  final Paint? foreground;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final double? fontSize;
  final FontStyle? fontStyle;
  final FontWeight? fontWeight;
  final TextDecoration? decoration;
  final Color? decorationColor;

  TextStyle({
    this.foreground,
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontSize,
    this.fontStyle,
    this.fontWeight,
    this.decoration,
    this.decorationColor,
  });
}

enum FontStyle { normal, italic }

enum FontWeight { w100, w200, w300, w400, w500, w600, w700, w800, w900 }

enum TextDecoration { none, lineThrough, overline, underline }

enum TextDirection { ltr, rtl }

enum TextBaseline { alphabetic, ideographic }

class SIPathBuilder implements EnhancedPathBuilder {
  final void Function(SIPathBuilder)? _onEnd;

  SIPathBuilder({void Function(SIPathBuilder)? onEnd}) : _onEnd = onEnd;

  final path = Path();

  @override
  void addOval(RectT rect) =>
      path.addOval(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height));

  @override
  void arcToPoint(
    PointT arcEnd, {
    required RadiusT radius,
    required double rotation,
    required bool largeArc,
    required bool clockwise,
  }) => path.arcToPoint(
    Offset(arcEnd.x, arcEnd.y),
    radius: Radius.elliptical(radius.x, radius.y),
    rotation: rotation * 180 / math.pi,
    largeArc: largeArc,
    clockwise: clockwise,
  );

  @override
  void close() => path.close();

  @override
  void cubicTo(PointT c1, PointT c2, PointT p, bool shorthand) =>
      path.cubicTo(c1.x, c1.y, c2.x, c2.y, p.x, p.y);

  @override
  void lineTo(PointT p) => path.lineTo(p.x, p.y);

  @override
  void moveTo(PointT p) => path.moveTo(p.x, p.y);

  @override
  void quadraticBezierTo(PointT control, PointT p, bool shorthand) =>
      path.quadraticBezierTo(control.x, control.y, p.x, p.y);

  @override
  void end() => _onEnd?.call(this);
}
