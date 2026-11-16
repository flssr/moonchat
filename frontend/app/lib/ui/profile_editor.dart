import 'package:flutter/material.dart';

import '../account_id.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../avatars.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'constellation.dart';
import 'widgets.dart';

/// 左下角头像打开的资料编辑。回填与保存都走 `GET` / `PUT /api/accounts/me`；
/// 登录与会话响应只带列表字段，所以打开时先拉一次完整资料。
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
  String _gender = 'private';
  DateTime? _birthday;
  String? _avatar;

  bool _loading = true;
  String? _loadError;
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
    _account = widget.state.account!;
    _name = TextEditingController(text: _account.displayName)
      ..addListener(() {
        if (_nameError != null) {
          setState(() => _nameError = null);
        }
      });
    _avatar = widget.state.avatarOf(_account.accountId);
    _loadProfile();
  }

  /// 头像不进 `PUT`：选中即落本机偏好，服务端还没有这一列。
  void _pickAvatar(String? key) {
    setState(() => _avatar = key);
    widget.state.setAvatar(_account.accountId, key);
  }

  /// 回填的唯一来源：`GET /api/accounts/me`。
  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final MyProfile profile = await widget.state.myProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _name.text = profile.displayName;
        _gender = profile.gender ?? 'private';
        _birthday = profile.birthday;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.isUnauthenticated) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _loading = false;
        _loadError = e.displayText;
      });
    }
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
      setState(() => _nameError = '昵称 1–20 字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    try {
      // `PUT` 是全量提交：三个字段都发，生日为 null 就是清空。
      await widget.state.updateProfile(
        displayName: name,
        gender: _gender,
        birthday: _birthday,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.isUnauthenticated) {
        // AppState 已经把界面切回登录页，收掉这个资料弹窗。
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = e.displayText);
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
                _header(context, p),
                if (_loading)
                  _loadingBody(context, p)
                else if (_loadError != null)
                  _errorBody(context, p, _loadError!)
                else
                  _form(context, p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, MoonPalette p) {
    return Row(
      children: <Widget>[
        Text(
          context.tr('个人资料'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
        ),
        const Spacer(),
        IconButton(
          tooltip: context.tr('关闭'),
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, size: 16, color: p.ink3),
        ),
      ],
    );
  }

  Widget _loadingBody(BuildContext context, MoonPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: p.ink3),
          ),
          const SizedBox(width: 10),
          Text(context.tr('加载中'), style: TextStyle(fontSize: 12, color: p.ink3)),
        ],
      ),
    );
  }

  Widget _errorBody(BuildContext context, MoonPalette p, String error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 16),
        Text(context.tr(error), style: TextStyle(fontSize: 11.5, color: p.accent)),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            MoonButton(label: context.tr('重试'), onPressed: _loadProfile),
            const SizedBox(width: 8),
            MoonButton(
              label: context.tr('取消'),
              kind: MoonButtonKind.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _form(BuildContext context, MoonPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            MoonAvatar(
              name: _account.displayName,
              seed: _account.accountId,
              avatar: _avatar,
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
                  MonoText('#${shortAccountId(_account.accountId)}', selectable: true),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('默认头像由平台提供，暂不支持上传；选中即生效，只保存在这台设备上。'),
                    style: TextStyle(fontSize: 11, height: 1.5, color: p.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.tr('选择默认头像'), style: _labelStyle(p)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _AvatarOption(
              label: context.tr('默认'),
              name: _account.displayName,
              seed: _account.accountId,
              selected: _avatar == null,
              onTap: _busy ? null : () => _pickAvatar(null),
            ),
            for (final (int i, String key) in avatarsFor(_account.type).indexed)
              _AvatarOption(
                label: '${context.tr('头像')} ${i + 1}',
                name: _account.displayName,
                seed: _account.accountId,
                avatar: key,
                selected: _avatar == key,
                onTap: _busy ? null : () => _pickAvatar(key),
              ),
          ],
        ),
        const SizedBox(height: 24),
        MoonField(
          label: context.tr('昵称'),
          controller: _name,
          enabled: !_busy,
          errorText: _nameError == null ? null : context.tr(_nameError!),
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
                onTap: _busy ? null : () => setState(() => _gender = key),
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
                    onTap: _busy ? null : () => setState(() => _birthday = null),
                    child: Text(
                      context.tr('清除'),
                      style: TextStyle(fontSize: 11, color: p.ink3),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.calendar_today_outlined, size: 16, color: p.ink3),
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
          Text(context.tr(_error!), style: TextStyle(fontSize: 11.5, color: p.accent)),
        ],
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            MoonButton(label: context.tr('保存'), busy: _busy, onPressed: _save),
            const SizedBox(width: 8),
            MoonButton(
              label: context.tr('取消'),
              kind: MoonButtonKind.text,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
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

/// 头像候选：外圈只表示选中，别把「默认」那张排除在外——它就是生成的首字头像。
class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.label,
    required this.name,
    required this.seed,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final String name;
  final int seed;
  final String? avatar;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: 1.5,
              color: selected ? p.ink : Colors.transparent,
            ),
          ),
          child: MoonAvatar(name: name, seed: seed, avatar: avatar, size: 36),
        ),
      ),
    );
  }
}
