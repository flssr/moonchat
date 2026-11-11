import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// S7 账号：我的真人账号与 agent、创建 agent、一次性密钥、切进账号。
class AccountView extends StatefulWidget {
  const AccountView({super.key, required this.state, required this.narrow});

  final AppState state;

  /// 外壳按整个客户端宽度判定的 ≤620：与消息页共用同一个断点来源。
  final bool narrow;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final TextEditingController _name = TextEditingController();
  CreatedAgent? _created;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _createAgent() async {
    final String name = _name.text.trim();
    if (name.isEmpty || name.length > 20) {
      setState(() => _error = '名字 1–20 字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final CreatedAgent created = await widget.state.createAgent(name);
      if (!mounted) {
        return;
      }
      _name.clear();
      setState(() => _created = created);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.displayText);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final Account? me = widget.state.account;
    final bool isHuman = me != null && !me.isAgent;

    return MoonSplitLayout(
      narrow: widget.narrow,
      list: _list(p, me, widget.narrow),
      detail: _detail(p, me, isHuman),
    );
  }

  Widget _list(MoonPalette p, Account? me, bool narrow) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: narrow
            ? Border(bottom: BorderSide(color: p.line))
            : Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        children: <Widget>[
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
                child: Text('账号', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.state.accounts.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Account a = widget.state.accounts[i];
                    final bool current = a.accountId == me?.accountId;
                    return Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      color: current ? p.surface2 : Colors.transparent,
                      child: Row(
                        children: <Widget>[
                          MoonAvatar(name: a.displayName, seed: a.accountId, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        a.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: p.ink),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    MoonTag(text: a.isAgent ? 'agent' : '真人'),
                                  ],
                                ),
                                MonoText('#${a.accountId}'),
                              ],
                            ),
                          ),
                          if (current)
                            MoonTag(text: '当前', strong: true)
                          else
                            MoonButton(
                              label: '切进',
                              kind: MoonButtonKind.secondary,
                              small: true,
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      try {
                                        await widget.state.switchAccount(a.accountId);
                                      } on ApiException catch (e) {
                                        if (context.mounted) {
                                          setState(() => _error = e.displayText);
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _busy = false);
                                        }
                                      }
                                    },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _detail(MoonPalette p, Account? me, bool isHuman) {
    return Container(
      color: p.bg,
      child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('当前账号', style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        MoonAvatar(name: me?.displayName ?? '', seed: me?.accountId ?? 0, size: 40),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              me?.displayName ?? '',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                            ),
                            MonoText('#${me?.accountId ?? ''}', selectable: true),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text('创建 agent 账号', style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
                    const SizedBox(height: 8),
                    if (!isHuman)
                      Text(
                        '当前是 agent 账号：agent 不能再建 agent。切回你的真人账号再创建。',
                        style: TextStyle(fontSize: 12, height: 1.6, color: p.ink3),
                      )
                    else ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: MoonField(label: '名字', controller: _name, hint: '1–20 字'),
                          ),
                          const SizedBox(width: 8),
                          MoonButton(label: '创建', busy: _busy, onPressed: _createAgent),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '新 agent 是孤立账号：不入群、不加好友，要聊天得先建立关系。',
                        style: TextStyle(fontSize: 11.5, height: 1.6, color: p.ink3),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(fontSize: 11.5, color: p.accent)),
                    ],
                    if (_created != null) ...<Widget>[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: p.surface,
                          border: Border.all(color: p.lineStrong),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '账号密钥（只显示一次）',
                              style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.accent),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _created!.accountKey,
                              style: TextStyle(fontSize: 12, height: 1.5, color: p.ink, fontFamilyFallback: kMonoFallback),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                MoonButton(
                                  label: '复制密钥',
                                  kind: MoonButtonKind.secondary,
                                  small: true,
                                  onPressed: () => copyText(context, _created!.accountKey, '密钥已复制'),
                                ),
                                const SizedBox(width: 8),
                                MoonButton(
                                  label: '我知道了',
                                  kind: MoonButtonKind.text,
                                  small: true,
                                  onPressed: () => setState(() => _created = null),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '离开这一页就不再显示。agent 端点用它换 Turms 凭据（POST /api/sessions）。',
                              style: TextStyle(fontSize: 11, height: 1.5, color: p.ink3),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text('凭据', style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.ink3)),
                    const SizedBox(height: 8),
                    Text(
                      '登录 JWT 7 天，滑动续期；Turms 凭据 12 小时，到期前重调 /api/sessions 换新的。'
                      '两者都由客户端自己续，不靠碰运气刚好没过期。',
                      style: TextStyle(fontSize: 12, height: 1.7, color: p.ink2),
                    ),
                  ],
                ),
                ),
              ),
            ),
    );
  }
}
