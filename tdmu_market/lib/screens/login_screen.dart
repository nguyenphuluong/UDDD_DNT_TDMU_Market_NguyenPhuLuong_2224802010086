import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';

const _studentDomain = '@student.tdmu.edu.vn';

enum _AuthMode { login, register, forgot }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onLogin});

  final ApiClient api;
  final ValueChanged<Map<String, dynamic>> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController server;
  final loginEmail = TextEditingController();
  final loginPassword = TextEditingController();
  final registerName = TextEditingController();
  final registerEmail = TextEditingController();
  final registerStudentId = TextEditingController();
  final registerMajor = TextEditingController();
  final registerPassword = TextEditingController();
  final registerCode = TextEditingController();
  final forgotEmail = TextEditingController();
  final forgotCode = TextEditingController();
  final forgotPassword = TextEditingController();

  _AuthMode mode = _AuthMode.login;
  bool loading = false;
  bool registerCodeSent = false;
  bool forgotCodeSent = false;
  bool showLoginPassword = false;
  bool showRegisterPassword = false;
  bool showForgotPassword = false;

  @override
  void initState() {
    super.initState();
    server = TextEditingController(text: widget.api.baseUrl);
  }

  @override
  void dispose() {
    server.dispose();
    loginEmail.dispose();
    loginPassword.dispose();
    registerName.dispose();
    registerEmail.dispose();
    registerStudentId.dispose();
    registerMajor.dispose();
    registerPassword.dispose();
    registerCode.dispose();
    forgotEmail.dispose();
    forgotCode.dispose();
    forgotPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAF7F4), bg],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              _brandHeader(),
              const SizedBox(height: 16),
              _ModeSwitch(mode: mode, onChanged: _changeMode),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (mode) {
                  _AuthMode.login => _loginPanel(),
                  _AuthMode.register => _registerPanel(),
                  _AuthMode.forgot => _forgotPanel(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: cardDecoration(radius: 24),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filledTonal(
              tooltip: 'Cài đặt kết nối',
              onPressed: _openServerSheet,
              icon: const Icon(Icons.tune_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFE3F4F0),
                foregroundColor: brandDark,
              ),
            ),
          ),
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/logoapp.jpg',
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'TDMU Market',
                  style: TextStyle(
                    color: ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chợ sinh viên Thu Dau Mot University',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginPanel() {
    return _AuthPanel(
      key: const ValueKey('login'),
      title: 'Đăng nhập',
      subtitle: 'Tiếp tục mua bán, nhắn tin và theo dõi đơn hàng.',
      child: Column(
        children: [
          _field(
            controller: loginEmail,
            label: 'Email',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _passwordField(
            controller: loginPassword,
            label: 'Mật khẩu',
            visible: showLoginPassword,
            onToggle: () =>
                setState(() => showLoginPassword = !showLoginPassword),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: loading ? null : () => _changeMode(_AuthMode.forgot),
              child: const Text('Quên mật khẩu?'),
            ),
          ),
          const SizedBox(height: 8),
          _primaryButton(
            label: 'Đăng nhập',
            icon: Icons.login_rounded,
            onPressed: _login,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : () => _changeMode(_AuthMode.register),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Tạo tài khoản sinh viên'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: brandDark,
              side: const BorderSide(color: Color(0xFF9BD5CC)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerPanel() {
    return _AuthPanel(
      key: const ValueKey('register'),
      title: 'Đăng ký sinh viên',
      subtitle: '',
      child: Column(
        children: [
          _field(
            controller: registerName,
            label: 'Họ tên',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _field(
            controller: registerEmail,
            label: 'Email sinh viên',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: registerStudentId,
                  label: 'Mã SV',
                  icon: Icons.credit_card_rounded,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: registerMajor,
                  label: 'Ngành học',
                  icon: Icons.school_outlined,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _passwordField(
            controller: registerPassword,
            label: 'Mật khẩu',
            visible: showRegisterPassword,
            onToggle: () =>
                setState(() => showRegisterPassword = !showRegisterPassword),
          ),
          if (registerCodeSent) ...[
            const SizedBox(height: 12),
            _field(
              controller: registerCode,
              label: 'Mã xác nhận',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: loading ? null : _requestRegisterCode,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Gửi lại mã'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _primaryButton(
            label: registerCodeSent
                ? 'Xác nhận và tạo tài khoản'
                : 'Gửi mã xác nhận',
            icon: registerCodeSent
                ? Icons.verified_rounded
                : Icons.mark_email_unread_outlined,
            onPressed:
                registerCodeSent ? _verifyRegister : _requestRegisterCode,
          ),
        ],
      ),
    );
  }

  Widget _forgotPanel() {
    return _AuthPanel(
      key: const ValueKey('forgot'),
      title: 'Quên mật khẩu',
      subtitle: 'Nhập email tài khoản để nhận mã đặt lại mật khẩu.',
      child: Column(
        children: [
          _field(
            controller: forgotEmail,
            label: 'Email tài khoản',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          if (forgotCodeSent) ...[
            const SizedBox(height: 12),
            _field(
              controller: forgotCode,
              label: 'Mã xác nhận',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: forgotPassword,
              label: 'Mật khẩu mới',
              visible: showForgotPassword,
              onToggle: () =>
                  setState(() => showForgotPassword = !showForgotPassword),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: loading ? null : _requestForgotCode,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Gửi lại mã'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _primaryButton(
            label: forgotCodeSent ? 'Đặt lại mật khẩu' : 'Gửi mã xác nhận',
            icon: forgotCodeSent
                ? Icons.lock_reset_rounded
                : Icons.mark_email_unread_outlined,
            onPressed: forgotCodeSent ? _resetPassword : _requestForgotCode,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: loading ? null : () => _changeMode(_AuthMode.login),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Quay lại đăng nhập'),
          ),
        ],
      ),
    );
  }

  Future<void> _openServerSheet() async {
    final previous = server.text;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDecoration(radius: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kết nối server',
                  style: TextStyle(
                    color: ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  controller: server,
                  label: 'Địa chỉ API',
                  icon: Icons.dns_outlined,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          server.text = previous;
                          Navigator.pop(context);
                        },
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          _applyServer();
                          Navigator.pop(context);
                          showSnack(context, 'Đã lưu địa chỉ server');
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return _field(
      controller: controller,
      label: label,
      icon: Icons.lock_outline_rounded,
      obscureText: !visible,
      suffixIcon: IconButton(
        tooltip: visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
        onPressed: onToggle,
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: brand,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  void _changeMode(_AuthMode value) {
    FocusScope.of(context).unfocus();
    setState(() => mode = value);
  }

  void _applyServer() {
    widget.api.baseUrl = server.text.trim().replaceAll(RegExp(r'/$'), '');
  }

  bool _validStudentEmail(String value) {
    return value.trim().toLowerCase().endsWith(_studentDomain);
  }

  void _showMailSent(Map<String, dynamic> data) {
    if (data['sent'] == true) {
      showSnack(context, 'Đã gửi mã xác nhận về email');
      return;
    }
    showSnack(context, 'Chưa cấu hình Gmail SMTP nên chưa gửi được email');
  }

  Future<void> _login() async {
    if (loginEmail.text.trim().isEmpty || loginPassword.text.trim().isEmpty) {
      showSnack(context, 'Vui lòng nhập email và mật khẩu');
      return;
    }
    setState(() => loading = true);
    try {
      _applyServer();
      final user =
          await widget.api.login(loginEmail.text.trim(), loginPassword.text);
      widget.onLogin(user);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _requestRegisterCode() async {
    if (registerName.text.trim().isEmpty ||
        registerEmail.text.trim().isEmpty ||
        registerStudentId.text.trim().isEmpty ||
        registerPassword.text.isEmpty) {
      showSnack(context, 'Vui lòng nhập đủ thông tin đăng ký');
      return;
    }
    if (!_validStudentEmail(registerEmail.text)) {
      showSnack(context, 'Email phải có đuôi $_studentDomain');
      return;
    }
    if (registerPassword.text.length < 6) {
      showSnack(context, 'Mật khẩu cần ít nhất 6 ký tự');
      return;
    }

    setState(() => loading = true);
    try {
      _applyServer();
      final data = await widget.api.requestRegisterCode(
        name: registerName.text.trim(),
        email: registerEmail.text.trim(),
        studentId: registerStudentId.text.trim(),
        major: registerMajor.text.trim().isEmpty
            ? 'Sinh viên TDMU'
            : registerMajor.text.trim(),
        password: registerPassword.text,
      );
      if (!mounted) return;
      setState(() => registerCodeSent = true);
      _showMailSent(data);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _verifyRegister() async {
    if (registerCode.text.trim().isEmpty) {
      showSnack(context, 'Vui lòng nhập mã xác nhận');
      return;
    }
    setState(() => loading = true);
    try {
      _applyServer();
      final user = await widget.api.verifyRegister(
        registerEmail.text.trim(),
        registerCode.text.trim(),
      );
      widget.onLogin(user);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _requestForgotCode() async {
    if (forgotEmail.text.trim().isEmpty) {
      showSnack(context, 'Vui lòng nhập email tài khoản');
      return;
    }
    setState(() => loading = true);
    try {
      _applyServer();
      final data =
          await widget.api.requestPasswordCode(forgotEmail.text.trim());
      if (!mounted) return;
      setState(() => forgotCodeSent = true);
      _showMailSent(data);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (forgotCode.text.trim().isEmpty || forgotPassword.text.isEmpty) {
      showSnack(context, 'Vui lòng nhập mã xác nhận và mật khẩu mới');
      return;
    }
    if (forgotPassword.text.length < 6) {
      showSnack(context, 'Mật khẩu cần ít nhất 6 ký tự');
      return;
    }
    setState(() => loading = true);
    try {
      _applyServer();
      await widget.api.resetPassword(
        email: forgotEmail.text.trim(),
        code: forgotCode.text.trim(),
        password: forgotPassword.text,
      );
      if (!mounted) return;
      loginEmail.text = forgotEmail.text.trim();
      loginPassword.clear();
      setState(() {
        mode = _AuthMode.login;
        forgotCodeSent = false;
      });
      showSnack(context, 'Đã đặt lại mật khẩu, bạn đăng nhập lại nhé');
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          _item('Đăng nhập', _AuthMode.login),
          _item('Đăng ký', _AuthMode.register),
          _item('Quên MK', _AuthMode.forgot),
        ],
      ),
    );
  }

  Widget _item(String label, _AuthMode value) {
    final selected = mode == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? brand : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : muted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
