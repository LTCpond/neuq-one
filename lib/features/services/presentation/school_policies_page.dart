import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/screen.dart';
import '../data/school_policies.dart';
import '../domain/school_policy.dart';

class SchoolPoliciesPage extends ConsumerWidget {
  const SchoolPoliciesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(schoolPoliciesProvider);
    final theme = Theme.of(context);
    return CampusScreen(
      title: '学校政策',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '文件来源：东北大学秦皇岛分校',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          DataPanel(
            value: catalog,
            retry: () => ref.invalidate(schoolPoliciesProvider),
            builder: (data) {
              final policies = data.policies;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.isOffline || data.updatedAt != null)
                    _CatalogStatus(data: data),
                  if (policies.isEmpty)
                    const StatePanel(
                      '暂无学校政策',
                      '政策发布后会显示在这里。',
                      icon: Icons.description_outlined,
                    ),
                  for (final policy in policies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: CampusIconBadge(
                            background: theme.colorScheme.primaryContainer,
                            foreground: theme.colorScheme.onPrimaryContainer,
                            child: const Icon(Icons.picture_as_pdf_outlined),
                          ),
                          title: Text(policy.shortTitle),
                          subtitle: Text('${policy.category} · PDF'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => _SchoolPolicyPreview(policy),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({required this.data});

  final SchoolPolicyCatalog data;

  @override
  Widget build(BuildContext context) {
    final updatedAt = data.updatedAt;
    final status = [
      if (data.isOffline) '离线缓存',
      if (updatedAt != null) '目录更新于 ${campusDateTimeLabel(updatedAt)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(status, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SchoolPolicyPreview extends ConsumerStatefulWidget {
  const _SchoolPolicyPreview(this.policy);

  final SchoolPolicy policy;

  @override
  ConsumerState<_SchoolPolicyPreview> createState() =>
      _SchoolPolicyPreviewState();
}

class _SchoolPolicyPreviewState extends ConsumerState<_SchoolPolicyPreview> {
  bool _saving = false;

  Future<void> _download(Uint8List bytes) async {
    setState(() => _saving = true);
    try {
      final saved = await ref.read(saveSchoolPolicyProvider)(
        widget.policy,
        bytes,
      );
      if (mounted && saved) showMessage(context, '政策 PDF 已保存');
    } catch (_) {
      if (mounted) showMessage(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy;
    final provider = schoolPolicyPdfProvider(policy);
    final pdf = ref.watch(provider);
    final bytes = pdf.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          policy.shortTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _saving ? '正在保存' : '下载 PDF',
            onPressed: bytes == null || _saving ? null : () => _download(bytes),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: pdf.when(
          data: (bytes) => _PolicyPdfView(bytes: bytes),
          loading: () => const _PdfLoading(),
          error: (_, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StatePanel(
                '暂时无法读取政策文件',
                '请检查网络连接后重试。',
                icon: Icons.error_outline,
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('重试'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyPdfView extends StatefulWidget {
  const _PolicyPdfView({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PolicyPdfView> createState() => _PolicyPdfViewState();
}

class _PolicyPdfViewState extends State<_PolicyPdfView> {
  late final _document = _openDocument();
  late var _page = _renderPage(1);
  var _pageNumber = 1;
  var _rendering = false;

  Future<PdfDocument> _openDocument() async {
    if (!await hasPdfSupport()) {
      throw UnsupportedError('当前平台暂不支持预览 PDF');
    }
    return PdfDocument.openData(widget.bytes);
  }

  Future<({Uint8List image, int pageCount})> _renderPage(int number) async {
    _rendering = true;
    try {
      final document = await _document;
      final page = await document.getPage(number);
      try {
        final scale = 2048 / math.max(page.width, page.height);
        final rendered = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (rendered == null) throw const FormatException('无法渲染 PDF 页面');
        return (image: rendered.bytes, pageCount: document.pagesCount);
      } finally {
        await page.close();
      }
    } finally {
      _rendering = false;
    }
  }

  void _showPage(int number) {
    if (_rendering) return;
    setState(() {
      _pageNumber = number;
      _page = _renderPage(number);
    });
  }

  Future<void> _closeDocument() async {
    try {
      // Android's renderer can close the document once the current page closes.
      await _page;
    } catch (_) {
      // Rendering failures still require closing the document.
    }
    try {
      await (await _document).close();
    } catch (_) {
      // Opening may have failed before a native document was created.
    }
  }

  @override
  void dispose() {
    unawaited(_closeDocument());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _page,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      if (snapshot.hasError) {
        return const Center(child: Text('暂时无法预览，可下载 PDF 后打开。'));
      }
      final rendered = snapshot.data;
      if (rendered == null) return const _PdfLoading();
      final number = _pageNumber;
      return Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: loading
                  ? const _PdfLoading()
                  : InteractiveViewer(
                      key: ValueKey(number),
                      maxScale: 4,
                      child: SizedBox.expand(
                        child: Image.memory(
                          rendered.image,
                          fit: BoxFit.contain,
                          semanticLabel: '政策原文第 $number 页',
                        ),
                      ),
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: loading || number == 1
                    ? null
                    : () => _showPage(number - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('第 $number / ${rendered.pageCount} 页'),
              IconButton(
                tooltip: '下一页',
                onPressed: loading || number == rendered.pageCount
                    ? null
                    : () => _showPage(number + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _PdfLoading extends StatelessWidget {
  const _PdfLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(semanticsLabel: '正在加载政策 PDF'),
  );
}
