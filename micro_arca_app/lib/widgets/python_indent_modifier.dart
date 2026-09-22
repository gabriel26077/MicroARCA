import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/widgets.dart';

/// Mantém a indentação ao digitar Enter e abre blocos Python com quatro espaços.
/// O CodeController só aplica modificadores a uma inserção simples, não a colagens.
class PythonIndentModifier extends CodeModifier {
  const PythonIndentModifier() : super('\n');

  @override
  TextEditingValue? updateString(
      String text, TextSelection selection, EditorParams params) {
    final cursor = selection.start;
    final start = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final line = text.substring(start, cursor);
    var indent = RegExp(r'^[ \t]*').stringMatch(line) ?? '';
    if (line.trimRight().endsWith(':') && !line.trimLeft().startsWith('#')) {
      indent += ' ' * params.tabSpaces;
    }
    return replace(text, cursor, selection.end, '\n$indent');
  }
}
