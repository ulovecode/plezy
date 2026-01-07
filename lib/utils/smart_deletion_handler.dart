import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../widgets/deletion_progress_dialog.dart';

class SmartDeletionHandler {
  /// 执行带有智能进度对话框的删除操作
  /// 只有当删除耗时超过 delayMs 时才会显示对话框
  static Future<void> deleteWithProgress({
    required BuildContext context,
    required DownloadProvider provider,
    required String globalKey,
    int delayMs = 500,
  }) async {
    bool dialogShown = false;
    bool deletionComplete = false;

    // 启动定时器，在延迟后显示对话框
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!deletionComplete && context.mounted) {
        dialogShown = true;
        _showProgressDialog(context, provider, globalKey);
      }
    });

    try {
      await provider.deleteDownload(globalKey);
    } finally {
      deletionComplete = true;
      // 如果对话框已显示则关闭它（使用 canPop 保护以防止重复 pop）
      if (dialogShown && context.mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    }
  }

  /// 显示进度对话框并监听更新
  static void _showProgressDialog(BuildContext context, DownloadProvider provider, String globalKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Consumer<DownloadProvider>(
        builder: (context, provider, child) {
          final progress = provider.getDeletionProgress(globalKey);

          // 如果没有进度，显示简单的回退 UI
          if (progress == null) {
            return const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(width: 20), Text('正在删除...')],
              ),
            );
          }

          return DeletionProgressDialog(progress: progress);
        },
      ),
    );
  }
}
