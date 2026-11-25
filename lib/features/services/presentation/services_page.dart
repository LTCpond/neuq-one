import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/campus_components.dart';
import '../data/campus_card_balance.dart';
import '../domain/services.dart';
import 'open_campus_service.dart';

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The indexed stack keeps this page mounted while other tabs are visible.
    if (TickerMode.valuesOf(context).enabled &&
        ModalRoute.isCurrentOf(context) == true) {
      ref.watch(campusCardRefreshProvider);
    }
    final balance = ref.watch(campusCardBalanceProvider).value;
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final cardInk = dark ? const Color(0xFFD5E2FF) : const Color(0xFF294593);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const CampusPageTitle('校园服务', eyebrow: 'NEUQ · CAMPUS LIFE'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 9),
            child: Text(
              'CAMPUS\nEXPLORE',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                height: 1.17,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const CampusSectionHeading('常用服务', caption: 'ESSENTIALS'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final classrooms = _ServiceFeature(
                service: classroomsService,
                height: 222,
                radius: 21,
                background: campusLime,
                foreground: const Color(0xFF293812),
                artwork: const _ServiceArt(
                  'classroom-door',
                  121,
                  118,
                  right: 23,
                  bottom: 3,
                ),
                titleSize: 24,
                subtitle: '找个地方专注学习',
                secondary: const Color(0xFF526D25),
              );
              final other = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ServiceFeature(
                    service: campusMailService,
                    height: 106,
                    background: Color(0xFF2649D8),
                    foreground: Colors.white,
                    artwork: _ServiceArt(
                      'mail-envelope',
                      71,
                      50,
                      right: 5,
                      bottom: 5,
                    ),
                    subtitle: '收发与查看邮件',
                    secondary: Color(0xFFDCE7FF),
                  ),
                  const SizedBox(height: 10),
                  _ServiceFeature(
                    service: campusCardService,
                    height: 106,
                    background: dark
                        ? const Color(0xFF293B60)
                        : const Color(0xFFE2E7FC),
                    foreground: cardInk,
                    artwork: const _ServiceArt(
                      'campus-card',
                      50,
                      38,
                      right: 8,
                      bottom: 5,
                    ),
                    value: balance == null
                        ? '—'
                        : campusCardMoney(balance.cents),
                    subtitle: balance == null ? '余额待同步' : '余额',
                    secondary: dark
                        ? const Color(0xFFAFC5F5)
                        : const Color(0xFF526DA3),
                  ),
                ],
              );
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [classrooms, const SizedBox(height: 10), other],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: classrooms),
                  const SizedBox(width: 10),
                  Expanded(child: other),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const CampusSectionHeading('教学', caption: 'STUDY'),
          const SizedBox(height: 8),
          const _ServicePair(academicServices),
          const SizedBox(height: 18),
          const CampusSectionHeading('办事与访问', caption: 'ACCESS'),
          const SizedBox(height: 8),
          const _ServicePair(accessServices),
          const SizedBox(height: 8),
          const _ServicePair([webVpnService, schoolPoliciesService]),
          const SizedBox(height: 18),
          const CampusSectionHeading('就业'),
          const SizedBox(height: 8),
          const _ServiceFeature(
            service: employmentService,
            height: 98,
            radius: 19,
            titleSize: 20,
            background: Color(0xFF252936),
            foreground: Colors.white,
            artwork: _ServiceArt(
              'employment-stairs',
              100,
              64,
              right: 16,
              bottom: 0,
            ),
            eyebrow: 'NEXT CHAPTER',
            secondary: Color(0xFFBEC9E2),
          ),
        ],
      ),
    );
  }
}

class _ServicePair extends StatelessWidget {
  const _ServicePair(this.services);

  final List<CampusService> services;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final singleColumn =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      if (singleColumn) {
        return Column(
          children: [
            _ServiceLink(services.first),
            const SizedBox(height: 8),
            _ServiceLink(services.last),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: _ServiceLink(services.first)),
          const SizedBox(width: 10),
          Expanded(child: _ServiceLink(services.last)),
        ],
      );
    },
  );
}

class _ServiceLink extends StatelessWidget {
  const _ServiceLink(this.service);

  final CampusService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final asset = switch (service.icon) {
      Icons.school_outlined => 'academic',
      Icons.map_outlined => 'map',
      Icons.apps_rounded => 'portal',
      Icons.wifi_rounded => 'wifi',
      Icons.vpn_lock_outlined => 'vpn',
      _ => null,
    };
    final (background, foreground) = switch (service.icon) {
      Icons.map_outlined =>
        dark
            ? (const Color(0xFF234B3A), const Color(0xFFADE3CA))
            : (const Color(0xFFD9EFE3), const Color(0xFF288264)),
      Icons.apps_rounded =>
        dark
            ? (const Color(0xFF563D25), const Color(0xFFFFD1A4))
            : (const Color(0xFFFFE8CF), const Color(0xFFA45717)),
      Icons.wifi_rounded =>
        dark
            ? (const Color(0xFF47365F), const Color(0xFFE2CCFF))
            : (const Color(0xFFE9E0FA), const Color(0xFF744BB4)),
      _ => (colors.primaryContainer, colors.primary),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        horizontalTitleGap: 9,
        leading: CampusIconBadge(
          background: background,
          foreground: foreground,
          child: asset == null
              ? Icon(service.icon)
              : Image.asset(
                  'assets/ui/service-$asset.png',
                  width: 24,
                  height: 24,
                  color: foreground,
                  excludeFromSemantics: true,
                ),
        ),
        title: Text(
          service.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        trailing: Icon(
          service == schoolPoliciesService
              ? Icons.chevron_right_rounded
              : Icons.open_in_new,
          size: 13,
          color: colors.onSurfaceVariant,
        ),
        onTap: () => openCampusService(context, service),
      ),
    );
  }
}

class _ServiceFeature extends StatelessWidget {
  const _ServiceFeature({
    required this.service,
    required this.height,
    required this.background,
    required this.foreground,
    required this.artwork,
    required this.secondary,
    this.titleSize = 17,
    this.radius = 18,
    this.eyebrow,
    this.subtitle,
    this.value,
  });

  final CampusService service;
  final double height;
  final Color background;
  final Color foreground;
  final Color secondary;
  final Widget artwork;
  final double titleSize;
  final double radius;
  final String? eyebrow;
  final String? subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) => Card(
    color: background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => openCampusService(context, service),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Stack(
          children: [
            artwork,
            Positioned(
              top: titleSize >= 20 ? 17 : 13,
              right: 12,
              child: Icon(Icons.chevron_right, color: foreground, size: 17),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 30, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrow case final label?) ...[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                  ],
                  Text(
                    service.name,
                    style: TextStyle(
                      fontSize: titleSize,
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (value case final label?)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.25,
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (subtitle case final label?) ...[
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ServiceArt extends StatelessWidget {
  const _ServiceArt(
    this.asset,
    this.width,
    this.height, {
    required this.right,
    required this.bottom,
  });

  final String asset;
  final double width;
  final double height;
  final double right;
  final double bottom;

  @override
  Widget build(BuildContext context) => Positioned(
    right: right,
    bottom: bottom,
    child: Image.asset(
      'assets/ui/$asset.png',
      width: width,
      height: height,
      excludeFromSemantics: true,
    ),
  );
}
