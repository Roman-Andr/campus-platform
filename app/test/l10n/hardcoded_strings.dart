import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Widgets whose positional string argument is shown to the user.
const _textWidgets = {'Text', 'SelectableText', 'TextSpan', 'Tooltip'};

/// Named parameters of Flutter widgets that are shown or read to the user.
const _textParameters = {
  'applicationLegalese',
  'applicationName',
  'counterText',
  'errorText',
  'helperText',
  'hintText',
  'label',
  'labelText',
  'message',
  'prefixText',
  'semanticLabel',
  'semanticsLabel',
  'semanticsValue',
  'subtitle',
  'suffixText',
  'text',
  'title',
  'tooltip',
};

final _letter = RegExp(r'\p{L}', unicode: true);
final _cyrillic = RegExp(r'\p{Script=Cyrillic}', unicode: true);

/// A user-facing string literal found outside the localization files.
class HardcodedString {
  const HardcodedString(this.path, this.line, this.text);

  final String path;
  final int line;
  final String text;

  @override
  String toString() => '$path:$line: $text';
}

/// Finds string literals in [source] that look like interface text:
/// arguments of text widgets, user-facing named parameters, and any
/// Cyrillic text.
List<HardcodedString> findHardcodedStrings(String path, String source) {
  final unit = parseString(content: source, path: path).unit;
  final visitor = _Visitor();
  unit.accept(visitor);
  return [
    for (final literal in visitor.found)
      HardcodedString(
        path,
        unit.lineInfo.getLocation(literal.offset).lineNumber,
        literal.toSource(),
      ),
  ];
}

class _Visitor extends RecursiveAstVisitor<void> {
  final found = <StringLiteral>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      _check(node, node.value);

  @override
  void visitStringInterpolation(StringInterpolation node) {
    final text = node.elements.whereType<InterpolationString>().map(
      (e) => e.value,
    );
    _check(node, text.join());
    super.visitStringInterpolation(node);
  }

  // Directives (`import '...'`) and annotations are not interface text.
  @override
  void visitImportDirective(ImportDirective node) {}

  @override
  void visitExportDirective(ExportDirective node) {}

  @override
  void visitPartDirective(PartDirective node) {}

  @override
  void visitAnnotation(Annotation node) {}

  void _check(StringLiteral node, String text) {
    if (node.parent is StringInterpolation || node.parent is AdjacentStrings) {
      return;
    }
    if (_cyrillic.hasMatch(text) ||
        (_letter.hasMatch(text) && _isInterfaceText(node))) {
      found.add(node);
    }
  }

  static bool _isInterfaceText(AstNode node) {
    final parent = node.parent;
    if (parent is NamedArgument) {
      return _textParameters.contains(parent.name.lexeme);
    }
    if (parent is ArgumentList) {
      final call = parent.parent;
      final name = switch (call) {
        InstanceCreationExpression() => call.constructorName.type.name.lexeme,
        MethodInvocation() => call.methodName.name,
        _ => null,
      };
      return _textWidgets.contains(name);
    }
    return false;
  }
}
