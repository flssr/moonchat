import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 注销账号：警告弹窗 + 当前密码确认 + 确认键 5 秒冷却（设置 → 隐私 → 注销账号）。
/// 成功后由 `AppState` 清本机会话并回登录页；服务端消息历史保留。
Future<void> showDeleteAccountDialog(BuildContext context, AppState state) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _DeleteAccountDialog(state: state),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.state});

  final AppState state;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const int _cooldownSeconds = 5;

  final TextEditingController _password = TextEditingController();
  Timer? _countdown;
  int _remaining = _cooldownSeconds;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 冷却只挡误触，不替代密码确认；每次打开都重新计时。
    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _remaining > 0) {
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = context.tr('密码不能为空'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.deleteAccount(password: _password.text);
      // 成功时 logout 已经让根导航收起弹窗；此处的 pop 只处理时序更慢的重建。
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.displayTextIn(context);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.tr('操作失败，请重试');
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
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.tr('注销账号'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 16, color: p.ink3),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('是否要注销账号，注销账号数据将不再保留'),
                style: TextStyle(fontSize: 13, height: 1.6, color: p.ink),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('账号资料、好友关系、群成员与名下 agent 会一并删除，消息历史保留。群主暂时不能注销。'),
                style: TextStyle(fontSize: 11.5, height: 1.6, color: p.ink3),
              ),
              const SizedBox(height: 16),
              MoonField(
                label: context.tr('密码'),
                controller: _password,
                obscure: true,
                hint: context.tr('输入当前密码确认'),
                errorText: _error,
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  if (_remaining > 0)
                    Expanded(
                      child: Text(
                        trArgs(context, '请稍候 {n} 秒', <String, String>{
                          'n': '$_remaining',
                        }),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: p.ink3,
                          fontFamilyFallback: kMonoFallback,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  MoonButton(
                    label: context.tr('取消'),
                    kind: MoonButtonKind.text,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  MoonButton(
                    label: context.tr('确认注销'),
                    kind: MoonButtonKind.danger,
                    busy: _busy,
                    onPressed: _remaining > 0 || _busy ? null : _confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
