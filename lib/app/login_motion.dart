import 'package:material_ui/material_ui.dart';

const loginEntranceDuration = Duration(milliseconds: 820);

bool loginMotionDisabled(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.reduceMotionOf(context);

Animation<double> loginPhase(
  Animation<double> entrance,
  int startMs,
  int endMs, {
  Curve curve = Curves.easeOutCubic,
}) => entrance.drive(
  CurveTween(
    curve: Interval(
      startMs / loginEntranceDuration.inMilliseconds,
      endMs / loginEntranceDuration.inMilliseconds,
      curve: curve,
    ),
  ),
);

class LoginReveal extends StatelessWidget {
  const LoginReveal({super.key, required this.progress, required this.child});

  final Animation<double> progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: progress,
    alwaysIncludeSemantics: true,
    child: AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 12 * (1 - progress.value)),
        child: child,
      ),
    ),
  );
}
