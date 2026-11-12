import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'constellation.dart';
import 'widgets.dart';

/// 左下角头像打开的资料编辑；头像仍由账号 id 生成，不在这里改。
Future<void> showProfileEditor(BuildContext context, AppState state) async {
  if (state.account == null) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => _ProfileEditor(state: state),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.state});

  final AppState state;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final Account _account;
  late final TextEditingController _name;
  late String _gender;
  DateTime? _birthday;

  String? _nameError;
  String? _error;
  bool _busy = false;

  static const List<(String, String)> _genders = <(String, String)>[
    ('male', '男'),
    ('female', '女'),
    ('other', '其他'),
    ('private', '保密'),
  ];

  @override
  void initState() {
    super.initState();
    // 登录 / 会话响应可能只带最小字段；`mine` 里同一账号的那份才是完整资料。
    _account = _resolveAccount(widget.state);
    _name = TextEditingController(text: _account.displayName)
      ..addListener(() {
        if (_nameError != null) {
          setState(() => _nameError = null);
        }
      });
    _gender = _account.gender ?? 'private';
    _birthday = _account.birthday;
  }

  Account _resolveAccount(AppState state) {
    final Account current = state.account!;
    for (final Account account in state.accounts) {
      if (account.accountId == current.accountId) {
        // `account` 由 updateProfile / 会话响应写入，一定是最新的；
        // 只有它缺资料字段时才用 mine 里的那份补全。
        final bool currentHasProfile =
            current.gender != null || current.birthday != null;
        return currentHasProfile ? current : account;
      }
    }
    return current;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(1900);
    final DateTime last = DateTime(now.year, now.month, now.day);
    DateTime initial = _birthday ?? DateTime(2000, 1, 1);
    if (initial.isBefore(first)) {
      initial = first;
    } else if (initial.isAfter(last)) {
      initial = last;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: context.tr('选择生日'),
      cancelText: context.tr('取消'),
      confirmText: context.tr('确定'),
    );
    if (picked != null) {
      setState(
        () => _birthday = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final String name = _name.text.trim();
    if (name.isEmpty || name.characters.length > 20) {
      setState(() => _nameError = context.tr('昵称 1–20 字'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    try {
      await widget.state.updateProfile(
        displayName: name,
        gender: _gender,
        birthday: _birthday,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
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
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.line),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      context.tr('个人资料'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: context.tr('关闭'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, size: 16, color: p.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    MoonAvatar(
                      name: _account.displayName,
                      seed: _account.accountId,
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _account.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.ink,
                            ),
                          ),
                          MonoText('#${_account.accountId}', selectable: true),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('头像由账号 ID 生成，暂不支持修改'),
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: p.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                MoonField(
                  label: context.tr('昵称'),
                  controller: _name,
                  enabled: !_busy,
                  errorText: _nameError,
                  hint: context.tr('1–20 字'),
                  onSubmitted: (_) {
                    if (!_busy) {
                      _save();
                    }
                  },
                ),
                const SizedBox(height: 18),
                Text(context.tr('性别'), style: _labelStyle(p)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final (String key, String label) in _genders)
                      MoonChoicePill(
                        label: context.tr(label),
                        selected: _gender == key,
                        onTap: _busy
                            ? null
                            : () => setState(() => _gender = key),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(context.tr('生日'), style: _labelStyle(p)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _busy ? null : _pickBirthday,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          _birthday == null
                              ? context.tr('选择生日')
                              : _formatBirthday(context, _birthday!),
                          style: TextStyle(
                            fontSize: 14,
                            color: _birthday == null ? p.ink3 : p.ink,
                          ),
                        ),
                        const Spacer(),
                        if (_birthday != null)
                          GestureDetector(
                            onTap: _busy
                                ? null
                                : () => setState(() => _birthday = null),
                            child: Text(
                              context.tr('清除'),
                              style: TextStyle(fontSize: 11, color: p.ink3),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: p.ink3,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text(context.tr('星座'), style: _labelStyle(p)),
                    const SizedBox(width: 12),
                    Text(
                      _birthday == null
                          ? context.tr('选择生日后自动计算')
                          : context.tr(constellationOf(_birthday!)),
                      style: TextStyle(
                        fontSize: 13,
                        color: _birthday == null ? p.ink3 : p.ink,
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    context.tr(_error!),
                    style: TextStyle(fontSize: 11.5, color: p.accent),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    MoonButton(label: context.tr('保存'), busy: _busy, onPressed: _save),
                    const SizedBox(width: 8),
                    MoonButton(
                      label: context.tr('取消'),
                      kind: MoonButtonKind.text,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(MoonPalette p) => TextStyle(
    fontSize: 10,
    letterSpacing: 1.1,
    color: p.ink3,
    fontFamilyFallback: kMonoFallback,
  );

  String _formatBirthday(BuildContext context, DateTime d) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'en':
        const List<String> months = <String>[
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return '${months[d.month - 1]} ${d.day}, ${d.year}';
      case 'de':
        return '${d.day}.${d.month}.${d.year}';
      case 'ja':
        return '${d.year}年${d.month}月${d.day}日';
      default:
        return '${d.year}年${d.month}月${d.day}日';
    }
  }
}
