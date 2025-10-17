import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import '../widgets/custom_action_bar.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  CodeController? _codeController;
  bool _keyboardVisible = false;

  final String _initialCode = """
# Welcome to MicroArca! 🚀
# Write your MicroPython code here

from machine import Pin
import time

led = Pin(2, Pin.OUT)

while True:
    led.on()
    print("LED is ON")
    time.sleep(1)
    led.off()
    print("LED is OFF")
    time.sleep(1)
""";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codeController = CodeController(
      text: _initialCode,
      language: python,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    final newValue = bottomInset > 0;
    if (newValue != _keyboardVisible) {
      setState(() => _keyboardVisible = newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: CodeTheme(
            data: const CodeThemeData(styles: a11yLightTheme),
            child: Column(
              children: [
                Expanded(
                  child: MicroArcaEditor(controller: _codeController),
                ),
              ],
            ),
          ),
        ),
      ),

      // ✅ Sem animações — some imediatamente quando o teclado aparece
      bottomNavigationBar: _keyboardVisible
          ? const SizedBox.shrink()
          : SizedBox(
              height: MediaQuery.of(context).size.height * 0.1,
              child: const CustomActionBar(),
            ),
    );
  }
}

class MicroArcaEditor extends StatefulWidget {
  const MicroArcaEditor({
    super.key,
    required this.controller,
  });

  final CodeController? controller;

  @override
  State<MicroArcaEditor> createState() => _MicroArcaEditorState();
}

class _MicroArcaEditorState extends State<MicroArcaEditor> {
  final FocusNode _focusNode = FocusNode();
  String _lastText = "";

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller?.text ?? "";
    widget.controller?.addListener(_scrollToCursor);
  }

  void _scrollToCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {});
    });
  }

  void _handleAutoIndent(String newText) {
    final controller = widget.controller;
    if (controller == null) return;

    if (newText.length > _lastText.length && newText.contains('\n')) {
      final newLineIndex = _findNewLineIndex(_lastText, newText);
      if (newLineIndex != -1) {
        _applyIndentation(controller, newText, newLineIndex);
      }
    }

    _lastText = newText;
  }

  int _findNewLineIndex(String oldText, String newText) {
    for (int i = 0; i < newText.length; i++) {
      if (i >= oldText.length || oldText[i] != newText[i]) {
        if (newText[i] == '\n') {
          return i;
        }
        break;
      }
    }
    return -1;
  }

  void _applyIndentation(CodeController controller, String text, int newLineIndex) {
    int lineStart = newLineIndex - 1;
    while (lineStart >= 0 && text[lineStart] != '\n') {
      lineStart--;
    }
    lineStart++;

    final String previousLine = text.substring(lineStart, newLineIndex);
    final String trimmedLine = previousLine.trim();

    final int currentIndent = _getIndentation(previousLine);
    final bool shouldIndent = _shouldIndentNextLine(trimmedLine);

    final int newIndent = currentIndent + (shouldIndent ? 4 : 0);
    final String indentSpaces = ' ' * newIndent;

    if (newIndent > 0) {
      final updatedText = text.replaceRange(
        newLineIndex + 1,
        newLineIndex + 1,
        indentSpaces,
      );
      controller.value = controller.value.copyWith(
        text: updatedText,
        selection: TextSelection.collapsed(
          offset: newLineIndex + 1 + indentSpaces.length,
        ),
      );
    }
  }

  bool _shouldIndentNextLine(String line) {
    final lineWithoutComments = line.split('#').first.trim();
    if (lineWithoutComments.isEmpty) return false;
    if (lineWithoutComments.endsWith(':')) return true;

    final indentKeywords = [
      'def', 'class', 'if', 'elif', 'else', 'while', 'for',
      'try', 'except', 'finally', 'with', 'async def', 'async for', 'async with'
    ];

    for (final keyword in indentKeywords) {
      if (lineWithoutComments.startsWith('$keyword ') ||
          lineWithoutComments == keyword) {
        return true;
      }
    }

    return false;
  }

  int _getIndentation(String line) {
    int indent = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        indent++;
      } else if (line[i] == '\t') {
        indent += 4;
      } else {
        break;
      }
    }
    return indent;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_scrollToCursor);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: CodeField(
          controller: widget.controller!,
          focusNode: _focusNode,
          lineNumbers: true,
          textStyle: const TextStyle(
            fontFamily: 'FiraCode',
            fontSize: 14,
          ),
          wrap: true,
          minLines: null,
          maxLines: null,
          onChanged: _handleAutoIndent,
        ),
      ),
    );
  }
}
