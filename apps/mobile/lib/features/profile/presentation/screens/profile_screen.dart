import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _openProfileRoute(String route) async {
    await context.push(route);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = _displayNameFor(user);
    final contact = _contactFor(user);
    final avatarUrl = _metadataValue(user, ['avatar_url', 'picture']);

    // Account for bottom nav: 76 (bar) + 12 (margin) + safe area bottom
    final bottomInset = MediaQuery.of(context).padding.bottom + 76 + 12 + 16;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.profile,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 380 ? 18.0 : 24.0;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    24,
                    padding,
                    bottomInset,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      const _ProfileHeader(),
                      const SizedBox(height: 24),
                      _ProfileIdentityCard(
                        name: displayName,
                        contact: contact,
                        avatarUrl: avatarUrl,
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle('Account'),
                      const SizedBox(height: 12),
                      _SettingsGroup(
                        items: [
                          _SettingsItemData(
                            icon: Icons.person_outline_rounded,
                            title: 'Personal Information',
                            subtitle: _personalInfoSubtitle(user),
                            onTap:
                                () => _openProfileRoute(
                                  AppRoutes.personalInformation,
                                ),
                          ),
                          _SettingsItemData(
                            icon: Icons.lock_outline_rounded,
                            title: 'Change Password',
                            subtitle: 'Update your password',
                            onTap:
                                () =>
                                    _openProfileRoute(AppRoutes.changePassword),
                          ),
                          const _SettingsItemData(
                            icon: Icons.mail_outline_rounded,
                            title: 'Email Preferences',
                            subtitle: 'Manage email notifications',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle('Support'),
                      const SizedBox(height: 12),
                      const _SettingsGroup(
                        items: [
                          _SettingsItemData(
                            icon: Icons.help_outline_rounded,
                            title: 'Help & Support',
                            subtitle: 'Get help for your queries',
                          ),
                          _SettingsItemData(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Send Feedback',
                            subtitle: 'Help us improve Raaste',
                          ),
                          _SettingsItemData(
                            icon: Icons.info_outline_rounded,
                            title: 'About Raaste',
                            subtitle: 'Learn more about the app',
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const _LogoutButton(),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'Version 1.0.0',
                          style: TextStyle(
                            color: RaasteShellColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _displayNameFor(User? user) {
    final fullName = _metadataValue(user, ['full_name', 'name']);
    if (fullName != null && fullName.trim().isNotEmpty) {
      return fullName.trim();
    }

    final firstName = _metadataValue(user, ['first_name'])?.trim() ?? '';
    final lastName = _metadataValue(user, ['last_name'])?.trim() ?? '';
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;

    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Traveller';
  }

  static String _contactFor(User? user) {
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!;
    }
    final phone = _phoneFor(user);
    if (phone != null) return phone;
    return 'No contact added';
  }

  static String? _phoneFor(User? user) {
    final metadataPhone = _metadataValue(user, [
      'phone_number',
      'phone',
      'mobile',
    ]);
    if (metadataPhone != null) return metadataPhone;
    final authPhone = user?.phone;
    if (authPhone != null && authPhone.trim().isNotEmpty) {
      return authPhone.trim();
    }
    return null;
  }

  static String _personalInfoSubtitle(User? user) {
    final bits = <String>[];
    if (user?.email != null && user!.email!.isNotEmpty) bits.add('email');
    if (_phoneFor(user) != null) bits.add('phone');
    bits.add('password');
    return bits.join(', ');
  }

  static String? _metadataValue(User? user, List<String> keys) {
    final metadata = user?.userMetadata;
    if (metadata == null) return null;
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder:
                    (context, c) => Text(
                      'Profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: RaasteShellColors.ink,
                        fontFamily: 'serif',
                        fontSize: c.maxWidth < 280 ? 32 : 38,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Manage your details and preferences',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: RaasteShellColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => showImplementingSoon(context),
            child: Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                border: Border.all(color: RaasteShellColors.outline),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: Colors.black87,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentityCard extends StatelessWidget {
  final String name;
  final String contact;
  final String? avatarUrl;

  const _ProfileIdentityCard({
    required this.name,
    required this.contact,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFE7D9C8), Color(0xFFFFFCF7), Color(0xFFDCE7D7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(23),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 330;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProfileAvatar(
                  name: name,
                  avatarUrl: avatarUrl,
                  radius: compact ? 34 : 40,
                ),
                SizedBox(width: compact ? 14 : 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: RaasteShellColors.ink,
                          fontFamily: 'serif',
                          fontSize: compact ? 22 : 26,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.mail_outline_rounded,
                            color: RaasteShellColors.muted,
                            size: 16,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              contact,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RaasteShellColors.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double radius;

  const _ProfileAvatar({
    required this.name,
    required this.avatarUrl,
    this.radius = 40,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();
    final imageProvider = avatarUrl == null ? null : NetworkImage(avatarUrl!);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Color(0xFFE9EFE4),
        shape: BoxShape.circle,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFDCE7D7),
        foregroundImage: imageProvider,
        child:
            avatarUrl == null
                ? Text(
                  initial,
                  style: TextStyle(
                    color: RaasteShellColors.sage,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w800,
                  ),
                )
                : null,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: RaasteShellColors.muted,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsItemData> items;

  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _SettingsRow(item: items[i]),
            if (i != items.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: RaasteShellColors.outline,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final _SettingsItemData item;

  const _SettingsRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap ?? () => showImplementingSoon(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          child: Row(
            children: [
              Icon(item.icon, color: Colors.black87, size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: RaasteShellColors.muted,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsItemData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF0EC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Supabase.instance.client.auth.signOut();
          if (context.mounted) context.go(AppRoutes.signIn);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFF1DAD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFA53527), size: 26),
              Expanded(
                child: Text(
                  'Log Out',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA53527),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Widget child;

  const _ProfileCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        border: Border.all(color: RaasteShellColors.outline),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
