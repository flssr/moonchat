import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// S1 登录 / 注册（`SCREEN-MAP.md` §4）。
/// 表单在左，右侧是静态舞台；发射那套动效已删除——它从来没被看见过（登录成功同一帧就换屏）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();

  bool _registerMode = false;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;
  String? _nameError;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  bool _validate() {
    final String email = _email.text.trim();
    final String password = _password.text;
    final String name = _name.text.trim();
    setState(() {
      _emailError = (email.isEmpty || !email.contains('@') || email.indexOf('@') == 0)
          ? '需要一个带 @ 的邮箱'
          : null;
      _passwordError = (password.length < 8 || password.length > 72)
          ? '密码 8–72 位'
          : int.tryParse(password) != null
              ? '密码不能是纯数字'
              : null;
      _nameError = !_registerMode
          ? null
          : (name.isEmpty || name.length > 20)
              ? '名字 1–20 字'
              : null;
      _formError = null;
    });
    return _emailError == null && _passwordError == null && _nameError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      if (_registerMode) {
        await widget.state.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _name.text.trim(),
        );
      }
      await widget.state.login(email: _email.text.trim(), password: _password.text);
    } on ApiException catch (e) {
      setState(() {
        if (e.isUnauthenticated) {
          _formError = '邮箱或密码不对';
        } else if (e.code == 'conflict') {
          _formError = '这个邮箱已经注册过了';
        } else {
          _formError = e.displayText;
        }
      });
    } catch (_) {
      setState(() => _formError = '操作失败，请重试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Scaffold(
      backgroundColor: p.bg,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool narrow = c.maxWidth < 900;
          final Widget form = _buildForm(context);
          final Widget stage = _buildStage(context);
          return Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1092),
                child: Padding(
                  padding: EdgeInsets.all(narrow ? 20 : 56),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: narrow
                          ? Column(
                              children: <Widget>[form, SizedBox(height: 300, child: stage)],
                            )
                          : SizedBox(
                              height: 540,
                              child: Row(
                                children: <Widget>[
                                  Expanded(flex: 44, child: form),
                                  Expanded(flex: 56, child: stage),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final MoonPalette p = context.moon;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(44, 44, 44, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'MoonChat',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.6,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '账号、好友、私聊、群聊。账号的能力可以被归属者之外的 agent 操控。',
            style: TextStyle(fontSize: 13, height: 1.7, color: p.ink3),
          ),
          const SizedBox(height: 28),
          if (_registerMode) ...<Widget>[
            MoonField(label: '名字', controller: _name, errorText: _nameError, hint: '1–20 字'),
            const SizedBox(height: 16),
          ],
          MoonField(
            label: '邮箱',
            controller: _email,
            errorText: _emailError,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          MoonField(
            label: '密码',
            controller: _password,
            obscure: true,
            errorText: _passwordError,
            hint: '8–72 位，不能是纯数字',
            onSubmitted: (_) => _submit(),
          ),
          if (_formError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_formError!, style: TextStyle(fontSize: 12, color: p.accent)),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              MoonButton(
                label: _registerMode ? '注册并登录' : '登录',
                onPressed: _submit,
                busy: _submitting,
              ),
              const SizedBox(width: 12),
              MoonButton(
                label: _registerMode ? '已有账号' : '注册',
                kind: MoonButtonKind.text,
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _registerMode = !_registerMode;
                          _formError = null;
                          _nameError = null;
                        }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    final MoonPalette p = context.moon;
    return Container(
      color: p.stage,
      child: Stack(
        children: <Widget>[
          // 地平线与月盘：只用描边与明度，不加渐变。
          Positioned(
            left: 0,
            right: 0,
            bottom: 96,
            child: Container(height: 1, color: p.ink3.withValues(alpha: 0.85)),
          ),
          Positioned(
            right: 56,
            top: 64,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: p.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: p.lineStrong),
              ),
            ),
          ),
          Center(
            child: Image.asset('assets/rocket-open.png', width: 240, fit: BoxFit.contain),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            child: Text(
              '月面基地',
              style: TextStyle(fontSize: 11, letterSpacing: 2, color: p.ink3, fontFamilyFallback: kMonoFallback),
            ),
          ),
        ],
      ),
    );
  }
}
