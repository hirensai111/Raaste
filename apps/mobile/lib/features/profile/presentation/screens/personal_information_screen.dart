import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _nameController.text = _displayNameFor(user);
    _emailController.text = user?.email ?? '';
    _phoneController.text = _phoneFor(user);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showMessage('Please sign in again to update your profile.');
      return;
    }

    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final nameParts = name.split(RegExp(r'\s+'));
    final firstName = nameParts.isEmpty ? name : nameParts.first;
    final lastName = nameParts.length <= 1 ? '' : nameParts.skip(1).join(' ');

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            ...?user.userMetadata,
            'name': name,
            'full_name': name,
            'first_name': firstName,
            'last_name': lastName,
            'phone': phone,
            'phone_number': phone,
          },
        ),
      );
      if (!mounted) return;
      _showMessage('Personal information updated.');
      _goBack(context);
    } on AuthException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not update personal information right now.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            _ProfileFormHeader(
              title: 'Personal Information',
              subtitle: 'Name, email, and phone',
              onBack: () => _goBack(context),
            ),
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              child: _FormCard(
                children: [
                  _ProfileTextField(
                    controller: _nameController,
                    label: 'Name',
                    icon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.mail_outline_rounded,
                    enabled: false,
                  ),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _phoneController,
                    label: 'Phone number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    validator: (value) {
                      final phone = (value ?? '').trim();
                      if (phone.isEmpty) return null;
                      if (phone.length < 7) return 'Enter a valid phone number';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _PrimaryActionButton(
              label: 'Save Changes',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  static String _displayNameFor(User? user) {
    final metadata = user?.userMetadata;
    final fullName = _metadataValue(metadata, ['full_name', 'name']);
    if (fullName != null) return fullName;

    final firstName = _metadataValue(metadata, ['first_name']) ?? '';
    final lastName = _metadataValue(metadata, ['last_name']) ?? '';
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;

    final email = user?.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return '';
  }

  static String _phoneFor(User? user) {
    final metadataPhone = _metadataValue(user?.userMetadata, [
      'phone_number',
      'phone',
      'mobile',
    ]);
    if (metadataPhone != null) return metadataPhone;
    return user?.phone ?? '';
  }

  static String? _metadataValue(
    Map<String, dynamic>? metadata,
    List<String> keys,
  ) {
    if (metadata == null) return null;
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    if (Supabase.instance.client.auth.currentUser == null) {
      _showMessage('Please sign in again to change your password.');
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text.trim()),
      );
      if (!mounted) return;
      _showMessage('Password updated.');
      _goBack(context);
    } on AuthException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not update password right now.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            _ProfileFormHeader(
              title: 'Change Password',
              subtitle: 'Update your account password',
              onBack: () => _goBack(context),
            ),
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              child: _FormCard(
                children: [
                  _ProfileTextField(
                    controller: _passwordController,
                    label: 'New password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    suffix: IconButton(
                      onPressed:
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().length < 6) {
                        return 'Use at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _confirmController,
                    label: 'Confirm password',
                    icon: Icons.lock_reset_rounded,
                    obscureText: _obscureConfirm,
                    suffix: IconButton(
                      onPressed:
                          () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim() !=
                          _passwordController.text.trim()) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _PrimaryActionButton(
              label: 'Update Password',
              loading: _saving,
              onPressed: _changePassword,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileFormHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _ProfileFormHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: RaasteShellColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;

  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final String? Function(String?)? validator;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      style: TextStyle(
        color: enabled ? RaasteShellColors.ink : RaasteShellColors.muted,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: RaasteShellColors.sage),
        suffixIcon: suffix,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF3EEE5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaasteShellColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaasteShellColors.outline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaasteShellColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaasteShellColors.clay),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: RaasteShellColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: loading ? null : onPressed,
      child:
          loading
              ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
              : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
    );
  }
}

void _goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go('/profile');
}
