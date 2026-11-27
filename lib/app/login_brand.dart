import 'package:material_ui/material_ui.dart';

import 'login_motion.dart';

class LoginBrand extends StatelessWidget {
  const LoginBrand({super.key, required this.entrance, required this.size});

  final Animation<double> entrance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displayMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: -size * .055,
      height: .88,
    );
    final accent = loginPhase(entrance, 300, 500);
    return Semantics(
      label: 'NEUQ One',
      header: true,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoginReveal(
              progress: loginPhase(entrance, 100, 450),
              child: Text('NEUQ', style: style),
            ),
            LoginReveal(
              progress: loginPhase(entrance, 180, 530),
              child: Text('One', style: style),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: accent,
              child: const SizedBox(
                width: 36,
                height: 4,
                child: ColoredBox(color: Color(0xFFFFB454)),
              ),
              builder: (context, child) => Transform.scale(
                scaleX: accent.value,
                scaleY: 1,
                alignment: Alignment.centerLeft,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
