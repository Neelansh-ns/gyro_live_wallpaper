import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

// Physics-based vector operations
class Vector2D {
  double x, y;

  Vector2D(this.x, this.y);

  Vector2D operator +(Vector2D other) => Vector2D(x + other.x, y + other.y);

  Vector2D operator *(double scalar) => Vector2D(x * scalar, y * scalar);

  double get magnitude => math.sqrt(x * x + y * y);

  Vector2D normalized() {
    double mag = magnitude;
    return mag > 0 ? Vector2D(x / mag, y / mag) : Vector2D(0, 0);
  }
}

class Vector3D {
  double x, y, z;

  Vector3D(this.x, this.y, this.z);

  Vector3D rotateX(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x, y * cos - z * sin, y * sin + z * cos);
  }

  Vector3D rotateY(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x * cos + z * sin, y, -x * sin + z * cos);
  }

  Vector3D rotateZ(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x * cos - y * sin, x * sin + y * cos, z);
  }

  Vector3D rotate(Vector3D rotation) {
    return rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);
  }
}

class Asteroid {
  // Position and movement
  Vector2D position;
  Vector2D velocity;
  Vector3D rotation = Vector3D(0, 0, 0);
  Vector3D rotationVelocity;

  // Physical properties
  final double size;
  final double depth;
  Color color;
  final List<Vector3D> vertices;

  // Visual properties
  final double glowIntensity;
  final double pulseRate;
  double pulsePhase = 0;

  double _colorChangeTime = 0;

  Asteroid({
    required this.position,
    required this.velocity,
    required this.rotationVelocity,
    required this.size,
    required this.depth,
    required this.color,
    required this.glowIntensity,
    required this.pulseRate,
  })  : vertices = _generateVertices(size),
        _colorChangeTime = -math.Random().nextDouble() * 2;

  static List<Vector3D> _generateVertices(double size) {
    final random = math.Random();

    // Function to generate triangle vertices with varied angles
    List<Vector3D> createIrregularTriangle() {
      // Randomize side lengths with some variance
      final sides = [
        size * (0.8 + random.nextDouble() * 0.4),
        size * (0.8 + random.nextDouble() * 0.4),
        size * (0.8 + random.nextDouble() * 0.4)
      ];

      // Randomize triangle type
      final triangleType = random.nextInt(3);

      List<double> angles;
      switch (triangleType) {
        case 0: // Acute triangle
          angles = [
            math.pi * 0.3 + random.nextDouble() * 0.4,
            math.pi * 0.3 + random.nextDouble() * 0.4,
            math.pi * 0.4 + random.nextDouble() * 0.4
          ];
          break;
        case 1: // Obtuse triangle
          angles = [
            math.pi * 0.6 + random.nextDouble() * 0.3,
            math.pi * 0.2 + random.nextDouble() * 0.3,
            math.pi * 0.2 + random.nextDouble() * 0.3
          ];
          break;
        default: // More equilateral-like
          angles = [
            math.pi / 3 + (random.nextDouble() - 0.5) * 0.4,
            math.pi / 3 + (random.nextDouble() - 0.5) * 0.4,
            math.pi / 3 + (random.nextDouble() - 0.5) * 0.4
          ];
      }

      // Calculate vertex positions
      return [
        Vector3D(0, 0, 0),
        Vector3D(
            sides[0] * math.cos(angles[0]), sides[0] * math.sin(angles[0]), (random.nextDouble() - 0.5) * size * 0.2),
        Vector3D(sides[1] * math.cos(0), sides[1] * math.sin(0), (random.nextDouble() - 0.5) * size * 0.2)
      ];
    }

    return createIrregularTriangle();
  }

  void update(double deltaTime, Size bounds) {
    // Update position with reduced velocity
    position = position + velocity * deltaTime;

    // Update 3D rotation
    rotation = Vector3D(rotation.x + rotationVelocity.x * deltaTime, rotation.y + rotationVelocity.y * deltaTime,
        rotation.z + rotationVelocity.z * deltaTime);

    final padding = size * 0.2;
    // Instead of wrapping, gently constrain to bounds and reverse velocity if needed
    if (position.x < (0 - padding) || position.x > (bounds.width + padding)) {
      velocity.x = -velocity.x * 0.8; // Reverse with some dampening
      position.x = position.x.clamp(0.0 - padding, bounds.width + padding);
    }

    if (position.y < (0 - padding) || position.y > (bounds.height + padding)) {
      velocity.y = -velocity.y * 0.8; // Reverse with some dampening
      position.y = position.y.clamp(0.0 - padding, bounds.height + padding);
    }

    // Update pulse phase
    pulsePhase += pulseRate * deltaTime;
  }

  List<Offset> getProjectedVertices() {
    // Project 3D vertices to 2D space
    return vertices.map((vertex) {
      final rotated = vertex.rotate(rotation);

      // Simple perspective projection
      final scale = 1 + (rotated.z / 200); // Adjust 200 for projection strength

      return Offset(
        position.x + rotated.x * scale,
        position.y + rotated.y * scale,
      );
    }).toList();
  }

  void updateColor(double currentTime) {
    // Each asteroid has its own offset for color change
    final phase = ((currentTime - _colorChangeTime) * 0.5).floor();

    if (phase > 0) {
      // Only change color for far/blurred asteroids
      if (depth > 0.4) {
        // Use the asteroid's unique hash to seed randomness
        final random = math.Random(hashCode * phase);
        color = backColors[random.nextInt(backColors.length)];

        // Reset the color change time
        _colorChangeTime = currentTime;
      }
    }
  }
}

class AsteroidField extends StatefulWidget {
  final int asteroidCount;
  final double maxDepth;

  const AsteroidField({
    super.key,
    this.asteroidCount = 20,
    required this.maxDepth,
  });

  @override
  AsteroidFieldState createState() => AsteroidFieldState();
}

class AsteroidFieldState extends State<AsteroidField> with SingleTickerProviderStateMixin {
  final List<Asteroid> asteroids = [];
  late final AnimationController _controller;
  double lastUpdateTime = 0;
  final random = math.Random();

  // Add gyroscope tracking
  double gyroOffsetX = 0;
  double gyroOffsetY = 0;
  static const double gyroSensitivity = 20.0;

  Color _getColorForDepth(double depth) {
    if (depth < 0.3) {
      return colors[random.nextInt(colors.length)];
    } else {
      return backColors[random.nextInt(backColors.length)];
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateAsteroids);
    _controller.repeat();
    lastUpdateTime = DateTime.now().millisecondsSinceEpoch / 1000;

    // Initialize gyroscope listening
    gyroscopeEventStream().listen((GyroscopeEvent event) {
      if (mounted) {
        setState(() {
          // Invert and adjust sensitivity for more natural feeling
          gyroOffsetX -= event.y * gyroSensitivity;
          gyroOffsetY += event.x * gyroSensitivity;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initAsteroids();
  }

  void _initAsteroids() {
    for (int i = 0; i < widget.asteroidCount; i++) {
      _addAsteroid();
    }
  }

  void _addAsteroid() {
    final depth = (0.1 + random.nextDouble() * 0.9).clamp(0, widget.maxDepth).toDouble();
    final baseSize = 10 + random.nextDouble() * 5;
    final asteroid = Asteroid(
      position: Vector2D(
        random.nextDouble() * MediaQuery.of(context).size.width,
        random.nextDouble() * MediaQuery.of(context).size.height,
      ),
      velocity: Vector2D(
        (random.nextDouble() - 0.5) * 5,
        (random.nextDouble() - 0.5) * 5,
      ),
      rotationVelocity: Vector3D(
        (random.nextDouble() - 0.5) * 1.2,
        (random.nextDouble() - 0.5) * 1.2,
        (random.nextDouble() - 0.5) * 1.2,
      ),
      size: baseSize * (1.5 - depth * 0.7),
      depth: depth,
      color: _getColorForDepth(depth),
      // Use depth-based color selection
      glowIntensity: 0.6 + random.nextDouble() * 0.4,
      pulseRate: 0.5 + random.nextDouble() * 2,
    );
    asteroids.add(asteroid);
  }

  void _updateAsteroids() {
    if (!mounted) return;

    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
    final deltaTime = currentTime - lastUpdateTime;
    lastUpdateTime = currentTime;

    setState(() {
      for (var asteroid in asteroids) {
        asteroid.update(deltaTime, MediaQuery.of(context).size);
        asteroid.updateColor(currentTime); // Add color update
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
    final size = MediaQuery.of(context).size;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: AsteroidPainter(
          asteroids: asteroids,
          canvasSize: size,
          gyroOffsetX: gyroOffsetX,
          gyroOffsetY: gyroOffsetY,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class AsteroidPainter extends CustomPainter {
  final List<Asteroid> asteroids;
  final Size canvasSize;
  final double gyroOffsetX;
  final double gyroOffsetY;

  AsteroidPainter({
    required this.asteroids,
    required this.canvasSize,
    required this.gyroOffsetX,
    required this.gyroOffsetY,
  });

  @override
  @override
  void paint(Canvas canvas, Size size) {
    // Rest of the painting code remains the same as in the original implementation
    final sortedAsteroids = [...asteroids]..sort((a, b) => b.depth.compareTo(a.depth));

    for (var asteroid in sortedAsteroids) {
      // Create a horizontal parallax effect based on depth and gyro tilt
      final horizontalOffset = gyroOffsetX * math.pow(1.1 - asteroid.depth, 3);

      final vertices = asteroid.getProjectedVertices().map((offset) {
        // Apply horizontal movement, with closer asteroids moving more
        return Offset(offset.dx + horizontalOffset, offset.dy);
      }).toList();

      // Rest of the rendering code remains the same
      final path = Path();
      path.moveTo(vertices[0].dx, vertices[0].dy);
      for (int i = 1; i < vertices.length; i++) {
        path.lineTo(vertices[i].dx, vertices[i].dy);
      }
      path.close();

      final depthFactor = asteroid.depth;

      if (depthFactor > 0.95) continue;

      // Create path without gyroscope adjustment (asteroids stay in place)
      // final path = Path();
      path.moveTo(vertices[0].dx, vertices[0].dy);
      for (int i = 1; i < vertices.length; i++) {
        path.lineTo(vertices[i].dx, vertices[i].dy);
      }
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..color = asteroid.color
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(AsteroidPainter oldDelegate) => true;
}

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: const AsteroidField(
                asteroidCount: 50,
                maxDepth: farDepthThreshold,
              ),
            ),
            const AsteroidField(
              asteroidCount: 30,
              maxDepth: 0,
            )
          ],
        ),
      ),
    ),
  ));
}

final List<Color> colors = [
  // Soft Whites
  const Color(0xFFFFFAF0), // Antique white
  const Color(0xFFFFFDD0), // Cream
  const Color(0xFFFFFACD), // Lemon chiffon

  // Pale Variations
  const Color(0xFFF0F8FF), // Alice blue
  const Color(0xFFF0FFFF), // Azure
  const Color(0xFFE6E6FA), // Lavender
  const Color(0xFFFFFAF0), // Floral white

  // Subtle Tints
  const Color(0xFFFFE4E1), // Misty rose
  const Color(0xFFF5F5F5), // White smoke
  const Color(0xFFFDF5E6), // Old lace
  const Color(0xFFFFFFF0), // Lavender
];

// In AsteroidFieldState
final backColors = [
  const Color(0xFF8B008B),
  const Color(0xFFDDA0DD), // Plum
  const Color(0xFFBA55D3), // Medium orchid
  const Color(0xFFFF69B4),
  const Color(0xFFFF1493),
  const Color(0xFF9932CC),
  const Color(0xFFFFA07A),
  const Color(0xFFFFB6C1),
  const Color(0xFFDA70D6),
  const Color(0xFF800080),

  // Deep Space Blues
  const Color(0xFF0C0F33), // Deep midnight blue
  const Color(0xFF1C2541), // Dark navy
  const Color(0xFF1F4068), // Deep space blue

  // Nebula Purples
  const Color(0xFF4A0E4E), // Deep plum
  const Color(0xFF5D3FD3), // Iris purple
  const Color(0xFF6A0DAD), // Royal purple

  // Cosmic Teals and Greens
  const Color(0xFF003B46), // Deep teal
  const Color(0xFF004445), // Dark sea green
  const Color(0xFF2C5F2D), // Deep forest green

  // Stellar Magentas and Pinks
  const Color(0xFF5D2E8C), // Deep magenta
  const Color(0xFF6E2594), // Rich purple
  const Color(0xFF723D46), // Deep rose

  // Cosmic Neutrals
  const Color(0xFF36454F), // Charcoal
  const Color(0xFF2F4F4F), // Dark slate gray

  // Gaseous Hues
  const Color(0xFF4B0082), // Indigo
  const Color(0xFF663399), // Rebecca Purple
];

const farDepthThreshold = 0.45;
