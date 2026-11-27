import 'package:material_ui/material_ui.dart';

import '../core/auth/neuq_login_protocol.dart';
import '../core/auth/school_auth.dart';
import '../core/network/official_browser.dart';
import '../core/theme/app_theme.dart';
import 'login_motion.dart';

class SchoolLoginForm extends StatefulWidget {
  const SchoolLoginForm({
    super.key,
    required this.canRememberPassword,
    required this.onSubmit,
    this.canSubmit = true,
    this.initialFailure,
    this.standalone = false,
  });

  final bool canRememberPassword;
  final bool canSubmit;
  final SchoolRequestFailure? initialFailure;
  final bool standalone;
  final Future<void> Function(
    NeuqCredentials credentials,
    bool rememberPassword,
  )
  onSubmit;

  @override
  State<SchoolLoginForm> createState() => _SchoolLoginFormState();
}

class _SchoolLoginFormState extends State<SchoolLoginForm> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  SchoolRequestFailure? _failure;
  bool _rememberPassword = false;
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _failure = widget.initialFailure;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !widget.canSubmit || !_form.currentState!.validate()) {
      return;
    }
    final credentials = NeuqCredentials(_username.text.trim(), _password.text);
    final rememberPassword = widget.canRememberPassword && _rememberPassword;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() {
      _submitting = true;
      _failure = null;
      _obscurePassword = true;
    });
    try {
      await widget.onSubmit(credentials, rememberPassword);
    } on SchoolRequestFailure catch (error) {
      if (mounted) setState(() => _failure = error);
    } catch (_) {
      if (mounted) setState(() => _failure = SchoolRequestFailure.unavailable);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required FocusNode focus,
    required IconData icon,
    Widget? suffix,
  }) {
    if (!widget.standalone) return InputDecoration(labelText: label);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );

    return InputDecoration(
      labelText: label,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: border(colors.outlineVariant),
      focusedBorder: border(colors.primary),
      errorBorder: border(colors.error),
      focusedErrorBorder: border(colors.error),
      errorMaxLines: 2,
      prefixIcon: _LoginFieldIcon(focus: focus, icon: icon),
      suffixIcon: suffix,
    );
  }

  Widget _passwordToggle(Duration duration) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: _submitting
          ? null
          : () => setState(() => _obscurePassword = !_obscurePassword),
      tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
      color: colors.onSurfaceVariant,
      icon: AnimatedSwitcher(
        duration: duration,
        child: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          key: ValueKey(_obscurePassword),
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = loginMotionDisabled(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final failure = _failure;
    final error = failure == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    failure.message,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                if (failure.requiresOfficialLogin)
                  TextButton.icon(
                    onPressed: () =>
                        openOfficialPage(context, schoolWebEntry.toString()),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('在系统浏览器打开教务'),
                  ),
              ],
            ),
          );

    return PopScope(
      canPop: !_submitting,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _username,
              focusNode: _usernameFocus,
              readOnly: _submitting,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: '学号',
                focus: _usernameFocus,
                icon: Icons.person_outline,
              ),
              validator: (value) =>
                  schoolSubjectForStudentCode(value?.trim() ?? '') == null
                  ? '请输入有效学号'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              focusNode: _passwordFocus,
              readOnly: _submitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.done,
              decoration: _fieldDecoration(
                label: '统一身份认证密码',
                focus: _passwordFocus,
                icon: Icons.lock_outline,
                suffix: widget.standalone ? _passwordToggle(duration) : null,
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? '请输入密码' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (widget.canRememberPassword) ...[
              if (widget.standalone) const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _rememberPassword,
                onChanged: _submitting
                    ? null
                    : (value) =>
                          setState(() => _rememberPassword = value ?? false),
                title: Text(
                  '在此设备记住密码',
                  style: widget.standalone ? theme.textTheme.bodyMedium : null,
                ),
                subtitle: Text(
                  '加密保存在本机，用于教务续登及学校远程访问服务按需认证。',
                  style: widget.standalone
                      ? theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (widget.standalone)
              _LoginSubmitButton(
                submitting: _submitting,
                onPressed: widget.canSubmit && !_submitting ? _submit : null,
                duration: duration,
              )
            else if (_submitting)
              const LinearProgressIndicator()
            else
              FilledButton(
                onPressed: widget.canSubmit ? _submit : null,
                child: const Text('统一身份认证登录'),
              ),
            if (widget.standalone && duration != Duration.zero)
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: error == null
                    ? const SizedBox.shrink()
                    : TweenAnimationBuilder<double>(
                        key: ValueKey(failure),
                        duration: duration,
                        tween: Tween(begin: 0, end: 1),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: error,
                      ),
              )
            else
              ?error,
          ],
        ),
      ),
    );
  }
}

class _LoginFieldIcon extends StatelessWidget {
  const _LoginFieldIcon({required this.focus, required this.icon});

  final FocusNode focus;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = loginMotionDisabled(context)
        ? Duration.zero
        : const Duration(milliseconds: 167);
    return ListenableBuilder(
      listenable: focus,
      builder: (context, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: focus.hasFocus ? colors.primary : colors.onSurfaceVariant,
        ),
        duration: duration,
        builder: (context, color, _) => Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _LoginSubmitButton extends StatefulWidget {
  const _LoginSubmitButton({
    required this.submitting,
    required this.onPressed,
    required this.duration,
  });

  final bool submitting;
  final VoidCallback? onPressed;
  final Duration duration;

  @override
  State<_LoginSubmitButton> createState() => _LoginSubmitButtonState();
}

class _LoginSubmitButtonState extends State<_LoginSubmitButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _setPressed(widget.onPressed != null),
    onPointerUp: (_) => _setPressed(false),
    onPointerCancel: (_) => _setPressed(false),
    child: AnimatedScale(
      scale:
          _pressed &&
              widget.onPressed != null &&
              widget.duration != Duration.zero
          ? .98
          : 1,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: FilledButton(
        onPressed: widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: campusBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.submitting ? campusBlue : null,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Theme.of(context).textTheme.titleMedium,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: widget.submitting ? 0 : 1,
              child: const Text('统一身份认证登录', textAlign: TextAlign.center),
            ),
            if (widget.submitting)
              const Positioned.fill(
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                      semanticsLabel: '正在登录',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
