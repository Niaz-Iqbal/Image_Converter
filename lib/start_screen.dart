import 'package:flutter/material.dart';
import 'select_mode_screen.dart';
import 'dart:math' as math;

class StartScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;

  const StartScreen({super.key, required this.onThemeChanged});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoGlowAnimation;
  late List<Animation<double>> _letterAnimations;
  late Animation<double> _taglineAnimation;
  late Animation<double> _screenFadeAnimation;
  final String _appName = "Pixelette";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..forward();

    // Logo animations
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeInOutSine),
      ),
    );
    _logoScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutQuad),
      ),
    );
    _logoGlowAnimation = Tween<double>(begin: 0.0, end: 15.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeInOut),
      ),
    );

    // Letter animations for "Pixelette"
    _letterAnimations = List.generate(_appName.length, (index) {
      double start = 0.4 + (index * 0.08);
      double end = (0.8 + (index * 0.08)).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            start.clamp(0.0, 1.0),
            end,
            curve: Curves.easeOutExpo,
          ),
        ),
      );
    });

    // Tagline animation
    _taglineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 0.9, curve: Curves.easeInOutSine),
      ),
    );

    // Screen fade-out for transition
    _screenFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.9, 1.0, curve: Curves.easeOut),
      ),
    );

    // Navigate to SelectModeScreen after animations complete
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) {
        print('Navigating to SelectModeScreen...');
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    SelectModeScreen(onThemeChanged: widget.onThemeChanged),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    isDarkMode
                        ? [Colors.indigo.shade900, Colors.purple.shade900]
                        : [Colors.indigo.shade300, Colors.purple.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Particle effect
          CustomPaint(
            painter: ParticlePainter(controller: _controller),
            size: MediaQuery.of(context).size,
          ),
          // Main content with screen fade-out
          FadeTransition(
            opacity: _screenFadeAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScaleAnimation.value,
                        child: Opacity(
                          opacity: _logoFadeAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  isDarkMode ? Colors.black54 : Colors.white70,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(
                                    isDarkMode ? 0.4 : 0.2,
                                  ),
                                  blurRadius: _logoGlowAnimation.value,
                                  spreadRadius: _logoGlowAnimation.value / 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(60),
                              child: Image.asset(
                                'assets/logo1.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // App name (Pixelette)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_appName.length, (index) {
                        return AnimatedBuilder(
                          animation: _letterAnimations[index],
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(
                                0,
                                (1 - _letterAnimations[index].value) * 30,
                              ),
                              child: Opacity(
                                opacity: _letterAnimations[index].value,
                                child: Text(
                                  _appName[index],
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                    letterSpacing: 1.5,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(
                                          isDarkMode ? 0.3 : 0.2,
                                        ),
                                        offset: const Offset(1, 1),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tagline
                  AnimatedBuilder(
                    animation: _taglineAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, (1 - _taglineAnimation.value) * 20),
                        child: Opacity(
                          opacity: _taglineAnimation.value,
                          child: Text(
                            'Pixels Perfected, Instantly Yours',
                            style: TextStyle(
                              fontSize: 16,
                              fontStyle: FontStyle.normal,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.8,
                              ),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Particle painter for subtle pixel-like effects
class ParticlePainter extends CustomPainter {
  final AnimationController controller;
  final List<Particle> particles = List.generate(20, (_) => Particle());

  ParticlePainter({required this.controller}) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      particle.update(controller.value);
      final paint =
          Paint()
            ..color = Colors.white.withOpacity(particle.opacity)
            ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class Particle {
  double x = math.Random().nextDouble();
  double y = math.Random().nextDouble();
  double size = math.Random().nextDouble() * 1.2 + 0.3;
  double opacity = math.Random().nextDouble() * 0.3 + 0.1;
  double speed = math.Random().nextDouble() * 0.01 + 0.005;

  void update(double animationValue) {
    y -= speed; // Move upward for a lighter feel
    if (y < 0.0) {
      y = 1.0;
      x = math.Random().nextDouble();
      size = math.Random().nextDouble() * 1.2 + 0.3;
      opacity = math.Random().nextDouble() * 0.3 + 0.1;
    }
  }
}
