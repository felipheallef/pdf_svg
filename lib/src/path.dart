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

library;

import 'package:pdf_svg/src/svg_graph.dart';

import 'path_noui.dart';
import 'common_noui.dart';
import 'render.dart';

///
/// Builder of a PDF path.  See [EnhancedPathBuilder] for usage.
///
class UIPathBuilder extends SIPathBuilder {
  UIPathBuilder({super.onEnd});
}

///
/// An SVG node that lets the client specify the [Path] directly.  This can
/// be used with the SVG DOM API, by programmatically creating an instance
/// of this node, and inserting it into an SVG DOM, either in a [SvgGroup] or
/// into [SvgDOM.root].
///
abstract class SvgCustomPath implements SvgInheritableAttributesNode {
  ///
  /// The path to draw when this node is rendered.
  ///
  abstract Path path;

  ///
  /// Create a new custom path node.
  ///
  factory SvgCustomPath(Path path) => SvgCustomPathImpl(path);

  ///
  /// Convenience method to parse a path string, producing a PDF [Path].
  /// See [PathParser] for details on parsing.
  ///
  static Path parsePath(String source) {
    final b = UIPathBuilder();
    final p = PathParser(b, source);
    p.parse();
    return b.path;
  }
}

class SvgCustomPathImpl extends SvgCustomPathAbstract implements SvgCustomPath {
  @override
  Path path;

  SvgCustomPathImpl(this.path);

  SvgCustomPathImpl._cloned(SvgCustomPathImpl super.other)
    : path = Path.from(other.path),
      super.copy();

  @override
  SvgCustomPathImpl clone() => SvgCustomPathImpl._cloned(this);

  @override
  String get tagName => 'customPath';

  @override
  RectT? getUntransformedBounds(SvgTextStyle ta) {
    final b = path.getBounds();
    return RectT(b.left, b.top, b.width, b.height);
  }

  @override
  void addPathNode(SIBuilder<String, SIImageData> builder, SIPaint cascaded) {
    builder.addPath(path, cascaded);
  }

  @override
  void visitPaths(void Function(Object pathKey) f) => f(path);
}
