import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';

/// 显示常用对话框的工具函数

/// 显示删除确认对话框
/// 如果用户确认则返回 true，如果取消则返回 false
Future<bool> showDeleteConfirmation(BuildContext context, {required String title, required String message}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(t.common.delete),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

/// 显示用于创建/命名项目的文本输入对话框
/// 返回输入的文本，如果取消则返回 null
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  required String hintText,
  String? initialValue,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _TextInputDialog(title: title, labelText: labelText, hintText: hintText, initialValue: initialValue),
  );
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String hintText;
  final String? initialValue;

  const _TextInputDialog({required this.title, required this.labelText, required this.hintText, this.initialValue});

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.labelText, hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        TextButton(onPressed: _submit, child: Text(t.common.save)),
      ],
    );
  }
}
