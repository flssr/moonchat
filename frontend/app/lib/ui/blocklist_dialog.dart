import 'package:flutter/material.dart';

import '../account_id.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 黑名单管理：列出我拉黑的人，可以逐个解除（设置 → 隐私 → 黑名单管理）。
/// 拉黑是单向关系标记，解黑后对方的消息与申请照常能进来。
Future<void> showBlocklistDialog(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => _BlocklistDialog(state: state),
  );
}

class _BlocklistDialog extends StatefulWidget {
  const _BlocklistDialog({required this.state});

  final AppState state;

  @override
  State<_BlocklistDialog> createState() => _BlocklistDialogState();
}

class _BlocklistDialogState extends State<_BlocklistDialog> {
  List<BlocklistItem>? _items;
  String? _error;
  int? _busyAccountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<BlocklistItem> items = await widget.state.loadBlocklist();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.displayTextIn(context));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('加载失败，稍后再试'));
      }
    }
  }

  Future<void> _unblock(BlocklistItem item) async {
    setState(() {
      _busyAccountId = item.accountId;
      _error = null;
    });
    try {
      await widget.state.unblockAccount(item.accountId);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items?.where((BlocklistItem i) => i.accountId != item.accountId).toList();
        _busyAccountId = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.displayTextIn(context);
          _busyAccountId = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.tr('加载失败，稍后再试');
          _busyAccountId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    context.tr('黑名单管理'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 16, color: p.ink3),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(child: _body(p)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(MoonPalette p) {
    final List<BlocklistItem>? items = _items;
    if (items == null) {
      // 首次加载失败也要给一句话：只转圈等不到东西。
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(_error!, style: TextStyle(fontSize: 11.5, color: p.accent)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.4, color: p.ink3),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(fontSize: 11.5, color: p.accent)),
          ),
        if (items.isEmpty)
          MoonEmpty(
            title: context.tr('黑名单是空的'),
            hint: context.tr('拉黑的人会出现在这里，可以随时解除'),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final BlocklistItem item in items) ...<Widget>[
                    _row(item, p),
                    if (item != items.last) Divider(color: p.line, height: 1),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BlocklistItem item, MoonPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          MoonAvatar(
            name: item.displayName,
            seed: item.accountId,
            avatar: widget.state.avatarOf(item.accountId),
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.ink),
                ),
                Text(
                  '#${shortAccountId(item.accountId)}',
                  style: TextStyle(fontSize: 11, color: p.ink3, fontFamilyFallback: kMonoFallback),
                ),
              ],
            ),
          ),
          MoonButton(
            label: context.tr('解除'),
            kind: MoonButtonKind.secondary,
            small: true,
            busy: _busyAccountId == item.accountId,
            onPressed: () => _unblock(item),
          ),
        ],
      ),
    );
  }
}
