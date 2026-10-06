import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import 'document_viewer_screen.dart';

/// Screen for managing soft-deleted documents (Recycle Bin / سلة المحذوفات).
/// Allows restoring or permanently purging documents within a 30-day window.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localDocumentStoreProvider).purgeExpiredTrash();
    });
  }

  Future<void> _restoreDocument(PendingUpload doc) async {
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .restoreFromTrash(doc.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تمت استعادة "${doc.title}" إلى المكتبة بنجاح'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmPermanentDelete(PendingUpload doc) async {
    final palette = context.appThemePalette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'حذف نهائي لا يمكن الرجوع عنه',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Text(
          'هل أنت متأكد من حذف "${doc.title}" نهائياً من ذاكرة الجهاز؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائياً'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .permanentlyDelete(doc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف "${doc.title}" نهائياً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmEmptyTrash(int count) async {
    if (count == 0) return;
    final palette = context.appThemePalette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تفريغ سلة المحذوفات بالكامل',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Text(
          'سيتم حذف جميع المستندات ($count) نهائياً من وحدة التخزين ولن تستطيع استعادتها أبداً.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تفريغ السلة الآن'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(pendingUploadsControllerProvider.notifier).emptyTrash();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفريغ سلة المحذوفات بالكامل'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appThemePalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trashAsync = ref.watch(trashUploadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سلة المحذوفات',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              'تحفظ الملفات لمدة 30 يوماً قبل الحذف التلقائي',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          trashAsync.maybeWhen(
            data: (items) => items.isNotEmpty
                ? IconButton(
                    tooltip: 'تفريغ السلة',
                    icon: Icon(Icons.delete_sweep_rounded, color: palette.danger),
                    onPressed: () => _confirmEmptyTrash(items.length),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ في تحميل المحذوفات: $err')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'سلة المحذوفات فارغة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'المستندات التي تحذفها تبقى هنا 30 يوماً ويمكنك استعادتها',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = items[index];
              final daysLeft = doc.daysRemainingInTrash;
              final isUrgent = daysLeft <= 5;

              return Dismissible(
                key: Key('trash_${doc.id}'),
                direction: DismissDirection.horizontal,
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    // Restore
                    await _restoreDocument(doc);
                    return true;
                  } else {
                    // Permanent delete
                    await _confirmPermanentDelete(doc);
                    return false;
                  }
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: palette.success.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.restore_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'استعادة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                secondaryBackground: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: palette.danger.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'حذف نهائي',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.delete_forever_rounded, color: Colors.white),
                    ],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: doc.previewImagePath != null &&
                                PendingUpload.isImageFilePath(
                                    doc.previewImagePath) &&
                                File(doc.previewImagePath!).existsSync()
                            ? Image.file(
                                File(doc.previewImagePath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color:
                                      palette.accent.withValues(alpha: 0.12),
                                  child: Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: palette.accent,
                                  ),
                                ),
                              )
                            : Container(
                                color: palette.accent.withValues(alpha: 0.12),
                                child: Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: palette.accent,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          '${formatFileSize(doc.fileSizeBytes)} • ${formatDate(doc.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isUrgent ? palette.danger : palette.warning)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'متبقي $daysLeft يوماً قبل الحذف التلقائي',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isUrgent ? palette.danger : palette.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'استعادة',
                          icon: Icon(Icons.restore_rounded, color: palette.success),
                          onPressed: () => _restoreDocument(doc),
                        ),
                        IconButton(
                          tooltip: 'حذف نهائي',
                          icon: Icon(Icons.delete_forever_rounded,
                              color: palette.danger),
                          onPressed: () => _confirmPermanentDelete(doc),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DocumentViewerScreen(document: doc),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
