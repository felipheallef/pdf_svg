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
/// We define the exported items in a sub-package so that we can
/// selectively export from it
///
library;

import 'dart:convert' show Encoding, utf8;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'affine.dart';
import 'avd_parser.dart';
import 'common.dart';
import 'common_noui.dart';
import 'compact.dart';
import 'dag.dart';
import 'render.dart';
import 'svg_parser.dart';

///
/// An image-like asset that can be scaled to any size and rendered without
/// losing resolution, typically derived from an SVG file.
/// This class features several
/// static methods to load a [ScalableImage] from various sources.  It
/// provides two in-memory representations:  a memory-saving "compact"
/// representation, as well as a faster internal graph structure.  Provision
/// is given to set a viewport, and prune away nodes that are outside
/// this viewport.  In this way, several smaller "views" onto a larger
/// SI asset can be produced, with maximal resource sharing between the
/// different assets.
///
/// A [ScalableImage] can be painted directly into a PDF graphics canvas.
///
/// Note that rendering a scalable image can be time-consuming if the
/// underlying scene is complex.  Notably, GPU performance can be a
/// bottleneck.  In this PDF fork, embedded images are decoded and embedded
/// synchronously as part of painting.
///
@immutable
abstract class ScalableImage {
  /// Width of the image, in pixels, if it was specified.  This corresponds
  /// to the SVG tag's `width` attribute, and the AVD vector element's
  /// `android:width`, if specified, or by `android:viewportWidth` if not.
  final double? width;

  /// Height of the image, in pixels, if it was specified.  This corresponds
  /// to the SVG tag's `height` attribute, and the AVD vector element's
  /// `android:height`, if specified, or `android:viewportHeight` if not.
  final double? height;

  /// [BlendMode] for applying the [tintColor].
  final BlendMode tintMode;

  /// Color used to tint the ScalableImage.  This feature, inspired by
  /// Android's tinting, allows you to apply a tint color to the entire asset.
  /// This can be used, for example, to color icons according to an application
  /// theme.
  final Color? tintColor;

  ///
  /// The currentColor value, as defined by
  /// [Tiny s. 11.2](https://www.w3.org/TR/2008/REC-SVGTiny12-20081222/painting.html#SpecifyingPaint).
  /// This is a color value in an SVG document for elements whose color is
  /// controlled by the SVG's container.
  ///
  final Color currentColor;

  ///
  /// Constructor intended for internal use.  See the static
  /// methods to create a ScalableImage.
  ///
  const ScalableImage._p(
    this.width,
    this.height,
    this.tintColor,
    this.tintMode,
    Color? currentColor,
  ) : currentColor = currentColor ?? ScalableImageBase.defaultCurrentColor;

  ///
  /// Give the viewport for this scalable image, in pixels.  By default,
  /// it's determined by the parameters in the original asset, but see also
  /// [ScalableImage.withNewViewport].  If the original SVG asset didn't
  /// define a width and height, they will be calculated the first time the
  /// viewport is requested.
  ///
  Rect get viewport;

  ///
  /// Return a copy of this SI with a different viewport.
  /// The bulk of the data is shared between the original and the copy.
  /// If prune is true, it attempts to prune paths that are outside of
  /// the new viewport.  Pruning away unneeded nodes will speed up
  /// rendering of the resulting [ScalableImage].
  ///
  /// Pruning is an expensive operation.  It relies on Flutter's calculations
  /// of the bounding box for the different graphical operations.  For stroked
  /// shapes, it adds the strokeWidth to that bounding box.
  ///
  /// The pruning tolerance allows you to prune away paths that are
  /// just slightly within the new viewport.  A positive sub-pixel
  /// tolerance might reduce the size of the new image with no
  /// discernible visual impact.
  ScalableImage withNewViewport(
    Rect viewport, {
    bool prune = false,
    double pruningTolerance = 0,
  });

  ///
  /// Return a new ScalableImage like this one, with tint modified.
  ///
  /// Note that the new instance shares most of its underlying state with the
  /// original, so it does not use much memory.
  ///
  ScalableImage modifyTint({
    required BlendMode newTintMode,
    required Color? newTintColor,
  });

  ///
  /// Return a new ScalableImage like this one, with currentColor
  /// modified.
  ///
  /// Note that the new instance shares most of its underlying state with the
  /// original, so it does not use much memory.
  ///
  ScalableImage modifyCurrentColor(Color newCurrentColor);

  ///
  /// Return a list of the ids of the nodes whose ids were exported, along with
  /// the bounding rectangle of that node.  An id might occur in the list
  /// multiple times, e.g. if the given node is referenced by `use` nodes
  /// in the underlying SVG.
  ///
  Set<ExportedID> get exportedIDs;

  ///
  /// Returns this SI as an in-memory directed acyclic graph of nodes.
  /// As compared to a compact scalable image, the DAG representation can
  /// be expected to render somewhat faster, at a significant cost in
  /// memory.  In informal measurements, the DAG representation's paint method
  /// ran about 3x faster.
  ///
  /// Note, however, that it would not be surprising for the dominant factor
  /// in framerate to be a bottleneck elsewhere in the rendering pipeline,
  /// e.g. in the GPU.  Under these circumstances, there might be no
  /// significant overall rendering performance difference between the compact
  /// and the DAG representations.
  ///
  /// Building a graph structure out of Dart objects might
  /// increase memory usage by an order of magnitude.
  ///
  /// If this image is already a DAG, this method just returns it.
  ///
  ScalableImage toDag();

  ///
  /// Give the bytes of the `.si` file representation of this [ScalableImage],
  /// if this is the compact representation.  If this is the DAG representation,
  /// throws a [StateError].  The compact representation is obtained
  /// by passing a `compact` flag when the image is created.
  ///
  /// See also the top-level documentation at https://pub.dev/packages/jovial_svg,
  /// under "Quick Loading Binary Format," and under "Goals and Package Evolution."
  ///
  Uint8List toSIBytes();

  ///
  /// Give a String that describes the size of this ScalableImage, for
  /// debugging.  For a compact image, this gives a size in bytes, and for
  /// the DAG representation, gives a node count.
  ///
  String debugSizeMessage();

  ///
  /// Create an image from the contents of a .si file in a ByteData.
  /// Loading a `.si` file is considerably faster than parsing an SVG
  /// or AVD file - about 5-20x faster in informal measurements.  A `.si`
  /// file can be created with `dart run jovial_svg:svg_to_si` or
  /// `dart run jovial_svg:avd_to_si`.
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static ScalableImage fromSIBytes(
    Uint8List bytes, {
    bool compact = false,
    Color? currentColor,
  }) {
    final r = ScalableImageCompact.fromBytes(bytes, currentColor: currentColor);
    if (compact) {
      return r;
    } else {
      return r.toDag();
    }
  }

  ///
  /// Parse an SVG XML string to a scalable image
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// See [ScalableImage.exportedIDs].
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static ScalableImage fromSvgString(
    String src, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
    List<Pattern> exportedIDs = const [],
    Color? currentColor,
  }) {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    if (compact) {
      final b = SICompactBuilder(
        warn: warnArg,
        currentColor: currentColor,
        bigFloats: bigFloats,
      );
      StringSvgParser(src, exportedIDs, b, warn: warnArg).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warnArg, currentColor: currentColor);
      StringSvgParser(src, exportedIDs, b, warn: warnArg).parse();
      return b.si;
    }
  }

  ///
  /// Parse an SVG XML document from a URL to a scalable image.  Usage:
  /// ```
  /// final si = await ScalableImage.fromSvgHttpUrl(
  ///     Uri.parse('https://jovial.com/images/jupiter.svg'));
  /// ```
  ///
  /// [url] is an http:, https: or data: Uri
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [httpHeaders] will be added to the HTTP GET request.
  ///
  /// [defaultEncoding] specifies the character encoding to use if the
  /// content-type header of the HTTP response does not indicate an encoding.
  /// RVC 2916 specifies latin1 for HTTP, but current browser practice defaults
  /// to UTF8.
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static Future<ScalableImage> fromSvgHttpUrl(
    Uri url, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
    List<Pattern> exportedIDs = const [],
    Color? currentColor,
    Encoding defaultEncoding = utf8,
    Map<String, String>? httpHeaders,
  }) async {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    return fromSvgString(
      await _getContent(url, defaultEncoding, httpHeaders),
      compact: compact,
      bigFloats: bigFloats,
      warnF: warnArg,
      exportedIDs: exportedIDs,
      currentColor: currentColor,
    );
  }

  ///
  /// Read a stream containing an SVG
  /// and parse it into a scalable image.
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [exportedIDs] specifies a list of node IDs that are to be exported.
  /// See [ScalableImage.exportedIDs].
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static Future<ScalableImage> fromSvgStream(
    Stream<String> stream, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
    List<Pattern> exportedIDs = const [],
  }) async {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    if (compact) {
      final b = SICompactBuilder(warn: warnArg, bigFloats: bigFloats);
      await StreamSvgParser(stream, exportedIDs, b, warn: warnArg).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warnArg);
      await StreamSvgParser(stream, exportedIDs, b, warn: warnArg).parse();
      return b.si;
    }
  }

  ///
  /// Parse an Android Vector Drawable XML string to a scalable image.
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the AVD asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  static ScalableImage fromAvdString(
    String src, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
  }) {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    if (compact) {
      final b = SICompactBuilder(warn: warnArg, bigFloats: bigFloats);
      StringAvdParser(src, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warnArg);
      StringAvdParser(src, b).parse();
      return b.si;
    }
  }

  ///
  /// Parse an Android Vector Drawable XML document from a URL to a scalable
  /// image.  Usage:
  /// ```
  /// final si = await ScalableImage.fromAvdHttpUrl(
  ///     Uri.parse('https://jovial.com/images/jupiter.avd'));
  /// ```
  ///
  /// [url] is an http:, https: or data: Uri
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the SVG asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  /// [httpHeaders] will be added to the HTTP GET request.
  ///
  /// [defaultEncoding] specifies the character encoding to use if the
  /// content-type header of the HTTP response does not indicate an encoding.
  /// RVC 2916 specifies latin1 for HTTP, but current browser practice defaults
  /// to UTF8.
  ///
  /// See also [ScalableImage.currentColor].
  ///
  static Future<ScalableImage> fromAvdHttpUrl(
    Uri url, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
    Encoding defaultEncoding = utf8,
    Map<String, String>? httpHeaders,
  }) async {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    return fromAvdString(
      await _getContent(url, defaultEncoding, httpHeaders),
      compact: compact,
      bigFloats: bigFloats,
      warnF: warnArg,
    );
  }

  static Future<String> _getContent(
    Uri url,
    Encoding defaultEncoding,
    Map<String, String>? httpHeaders,
  ) async {
    String? content = url.data?.contentAsString(encoding: defaultEncoding);
    if (content == null) {
      final client = http.Client();
      try {
        final response = await client.get(url, headers: httpHeaders);
        final ct = response.headers['content-type'];
        if (ct == null || !ct.toLowerCase().contains('charset')) {
          //  Use default if not specified in content-type header
          content = defaultEncoding.decode(response.bodyBytes);
        } else {
          content = response.body;
        }
      } finally {
        client.close();
      }
    }
    return content;
  }

  ///
  /// Read a stream containing an Android Vector Drawable in XML format
  /// and parse it into a scalable image.
  ///
  /// If [compact] is true, the internal representation will occupy
  /// significantly less memory, at the expense of rendering time.  See
  /// [toDag] for a discussion of the two representations.
  ///
  /// If [bigFloats] is true, the compact representation
  /// will use 8 byte double-precision float values, rather than 4 byte
  /// single-precision values.
  ///
  /// If [warnF] is non-null, it will be called if the AVD asset contains
  /// unrecognized tags and/or tag attributes.  If it is null, the default
  /// behavior is to print warnings.
  ///
  static Future<ScalableImage> fromAvdStream(
    Stream<String> stream, {
    bool compact = false,
    bool bigFloats = false,
    @Deprecated("[warn] has been superseded by [warnF].") bool warn = true,
    void Function(String)? warnF,
  }) async {
    final warnArg = warnF ?? (warn ? defaultWarn : nullWarn);
    if (compact) {
      final b = SICompactBuilder(warn: warnArg, bigFloats: bigFloats);
      await StreamAvdParser(stream, b).parse();
      return b.si;
    } else {
      final b = SIDagBuilder(warn: warnArg);
      await StreamAvdParser(stream, b).parse();
      return b.si;
    }
  }

  ///
  /// Creates a new instance of a blank image.
  ///
  static ScalableImage blank() => ScalableImageDag.blank();

  ///
  /// Paint this ScalableImage to the PDF graphics canvas [c].
  /// This method saves the canvas state, translates the
  /// canvas by the [viewport]'s origin, clips to the [viewport]'s size,
  /// paints the image, and restores the canvas.
  ///
  void paint(PdfGraphics c, {required PdfDocument document});
}

///
/// A non-exported base class, so we can hide the constructors and protected
/// members.
///
abstract class ScalableImageBase extends ScalableImage {
  ///
  /// The images within this [ScalableImage].
  ///
  @protected
  final List<SIImage> images;

  @protected
  final Rect? givenViewport;

  static const Color defaultCurrentColor = Colors.black;

  ///
  /// Constructor intended for internal use.  See the static
  /// methods to create a ScalableImage.
  ///
  ScalableImageBase(
    double? width,
    double? height,
    Color? tintColor,
    BlendMode tintMode,
    this.givenViewport,
    this.images,
    Color? currentColor,
  ) : super._p(width, height, tintColor, tintMode, currentColor);

  ///
  /// Constructor intended for internal use.  See the static
  /// methods to create a ScalableImage.
  ///
  ScalableImageBase.modifiedFrom(
    ScalableImageBase other, {
    required Rect? viewport,
    required Color currentColor,
    required Color? tintColor,
    required BlendMode tintMode,
    required this.images,
  }) : givenViewport = _newViewport(viewport, other.givenViewport),
       super._p(
         viewport?.width ?? other.width,
         viewport?.height ?? other.height,
         tintColor,
         tintMode,
         currentColor,
       );

  static Rect? _newViewport(Rect? incoming, Rect? old) {
    if (incoming == null) {
      return old;
    } else {
      return incoming;
    }
  }

  @override
  late final Rect viewport = _initViewport();

  Rect _initViewport() {
    if (givenViewport != null) {
      return givenViewport!;
    }
    double? w = width;
    double? h = height;
    if (w != null && h != null) {
      return Rect.fromLTWH(0, 0, w, h);
    }
    return (getBoundary(null, null)?.getBounds() ?? Rect.zero);
  }

  ///
  /// Protected method that calculates the boundary of this ScalableImage
  /// by doing a full tree traversal.
  ///
  @protected
  PruningBoundary? getBoundary(
    List<ExportedIDBoundary>? exportedIDs,
    Affine? exportedIDXform,
  );

  @override
  void paint(PdfGraphics c, {required PdfDocument document}) {
    final canvas = PdfCanvas(c, document);
    try {
      canvas.save();
      Rect vp = viewport;
      canvas.translate(0, vp.height);
      canvas.scale(1, -1);
      canvas.translate(-vp.left, -vp.top);
      canvas.clipRect(vp);
      final tc = tintColor;
      if (tc == null) {
        paintChildren(canvas, currentColor);
      } else {
        canvas.saveLayer(vp, Paint());
        canvas.save();
        try {
          paintChildren(canvas, currentColor);
        } finally {
          canvas.restore();
          canvas.drawColor(tc, tintMode);
          canvas.restore();
        }
      }
    } finally {
      canvas.restore();
    }
  }

  ///
  /// Protected method to paint the children of this ScalableImage.
  ///
  @protected
  void paintChildren(Canvas c, Color currentColor);

  @override
  late final Set<ExportedID> exportedIDs = _calculateExportedIDs();

  Set<ExportedID> _calculateExportedIDs() {
    final result = List<ExportedIDBoundary>.empty(growable: true);
    final MutableAffine xform = MutableAffine.identity();
    final Rect vp = viewport;
    xform.transformed(Point(-vp.left, -vp.right));
    getBoundary(result, xform);
    return Set.unmodifiable(
      result.map((e) => ExportedID(e.id, e.boundary.getBounds())),
    );
  }
}

///
/// A record of a node whose id was exported.  An ExportedID record gives the
/// bounding rectangle of one instance of the node with the given ID.  Multiple
/// bounding rectangles may be created for the same node, e.g. if that node
/// is `use`d multiple times in the SVG from which the [ScalableImage] was
/// created.
///
/// See also `ExportedIDLookup` in the `widgets` package.
///
class ExportedID {
  ///
  /// The ID of the node that produced this bounding rectangle.
  ///
  final String id;

  ///
  /// The bounding rectangle of the node, translated into the coordinate system
  /// of the top-level [ScalableImage].
  ///
  final Rect boundingRect;

  ExportedID(this.id, this.boundingRect);

  @override
  String toString() => 'EID($id, $boundingRect)';

  @override
  int get hashCode => Object.hash(id, boundingRect);

  @override
  bool operator ==(Object other) {
    if (other is ExportedID) {
      return id == other.id && boundingRect == other.boundingRect;
    } else {
      return false;
    }
  }
}

class ExportedIDBoundary {
  final String id;
  final PruningBoundary boundary;

  ExportedIDBoundary(this.id, this.boundary);
}
