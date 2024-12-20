// models.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

extension RandomExtension on math.Random {
  double nextGaussian() {
    double u1 = 1.0 - nextDouble();
    double u2 = 1.0 - nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

class Vector3D {
  final double x, y, z;

  const Vector3D(this.x, this.y, this.z);

  Vector3D operator -(Vector3D other) => Vector3D(x - other.x, y - other.y, z - other.z);

  Vector3D operator +(Vector3D other) => Vector3D(x + other.x, y + other.y, z + other.z);

  Vector3D operator *(double scalar) => Vector3D(x * scalar, y * scalar, z * scalar);

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vector3D normalized() {
    final m = magnitude;
    if (m == 0) return const Vector3D(0, 0, 0);
    return Vector3D(x / m, y / m, z / m);
  }

  Vector3D cross(Vector3D other) {
    return Vector3D(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x,
    );
  }

  double dot(Vector3D other) {
    return x * other.x + y * other.y + z * other.z;
  }

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
}

class Asteroid {
  final Vector3D position;
  Vector3D rotation;
  final Vector3D rotationVelocity;
  final double size;
  final List<Vector3D> vertices;
  Color color;
  bool _isDirty = true;
  List<Offset>? _cachedProjection;

  Asteroid({
    required this.position,
    required this.rotationVelocity,
    required this.size,
    required this.color,
  })  : rotation = const Vector3D(0, 0, 0),
        vertices = _generateVertices(size);

  static List<Vector3D> _generateVertices(double size) {
    final random = math.Random();
    final baseWidth = size * (0.2 + random.nextDouble() * 0.3);
    final height = size * (0.8 + random.nextDouble() * 1.2);
    final baseOffset = size * (random.nextDouble() - 0.5) * 0.2;
    final zVariation = size * 0.05;

    return [
      Vector3D(baseOffset, 0, (random.nextDouble() - 0.5) * zVariation),
      Vector3D(baseOffset + baseWidth, 0, (random.nextDouble() - 0.5) * zVariation),
      Vector3D(
        baseOffset + (baseWidth * (0.4 + random.nextDouble() * 0.2)),
        -height,
        (random.nextDouble() - 0.5) * zVariation,
      ),
    ];
  }

  void update(double deltaTime) {
    rotation = Vector3D(
      rotation.x + rotationVelocity.x * deltaTime,
      rotation.y + rotationVelocity.y * deltaTime,
      rotation.z + rotationVelocity.z * deltaTime,
    );
    _isDirty = true;
  }

  List<Offset> project(Vector3D cameraPos, Vector3D forward, Vector3D right, Vector3D up, double fov) {
    if (!_isDirty && _cachedProjection != null) return _cachedProjection!;

    final relativePos = position - cameraPos;
    final depth = relativePos.dot(forward);

    if (depth <= 0) return const []; // Behind camera

    final scale = fov / depth;
    final screenX = relativePos.dot(right) * scale;
    final screenY = relativePos.dot(up) * scale;

    _cachedProjection = vertices.map((vertex) {
      final rotated = vertex.rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);
      final vertexScale = scale * (1 + rotated.z / 200);
      return Offset(
        screenX + rotated.x * vertexScale,
        screenY + rotated.y * vertexScale,
      );
    }).toList();

    return _cachedProjection!;
  }
}

// Color configurations
const shardColors = [
  Colors.white,
  Color(0xFFF0F8FF), // Alice Blue
  Color(0xFFFFFAFA), // Snow
  Color(0xFFF0FFFF), // Azure
];

const accentColors = [
  Color(0xFF4169E1), // Royal Blue
  Color(0xFF9370DB), // Medium Purple
  Color(0xFF3CB371), // Medium Sea Green
  Color(0xFFFF6347), // Tomato
  Color(0xFFFFD700), // Gold
];

class AsteroidField extends StatefulWidget {
  final int asteroidCount;

  const AsteroidField({
    super.key,
    this.asteroidCount = 30,
  });

  @override
  AsteroidFieldState createState() => AsteroidFieldState();
}

class AsteroidFieldState extends State<AsteroidField> with SingleTickerProviderStateMixin {
  static const double hemisphereRadius = 400.0;
  static const double maxTiltAngle = 60 * math.pi / 180;
  static const double cameraSensitivity = 0.15;
  static const double cameraInertia = 0.90;
  static const double fov = 800.0;

  List<Asteroid> asteroids = [];
  late final AnimationController _controller;
  double lastUpdateTime = 0;
  double cameraX = 0;
  double cameraY = 0;
  final random = math.Random();

  static const double baseDistance = 1200.0; // Initial camera distance
  static const double minDistance = 600.0; // Closest zoom
  static const double maxDistance = 2000.0; // Furthest zoom

  double _zoomLevel = 1.0;

  double get cameraDistance => baseDistance * (1 / _zoomLevel);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateAsteroids);
    _controller.repeat();

    lastUpdateTime = DateTime.now().millisecondsSinceEpoch / 1000;

    gyroscopeEventStream().listen((GyroscopeEvent event) {
      if (mounted) {
        setState(() {
          cameraX = (cameraX * cameraInertia - event.y * cameraSensitivity).clamp(-maxTiltAngle, maxTiltAngle);
          cameraY = (cameraY * cameraInertia + event.x * cameraSensitivity).clamp(-maxTiltAngle, maxTiltAngle);
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
    asteroids = List.generate(widget.asteroidCount, (_) {
      // Use gaussian distribution for more central concentration
      final r = (random.nextGaussian() * 0.3).abs() * hemisphereRadius;
      final phi = random.nextDouble() * 2 * math.pi;
      final theta = (random.nextGaussian() * 0.3).abs() * math.pi / 2;

      final x = r * math.sin(theta) * math.cos(phi);
      final y = r * math.sin(theta) * math.sin(phi);
      final z = r * math.cos(theta);

      final useAccentColor = random.nextDouble() < 0.2; // 20% chance for accent color
      final color = (useAccentColor
              ? accentColors[random.nextInt(accentColors.length)]
              : shardColors[random.nextInt(shardColors.length)])
          .withOpacity(0.9);

      return Asteroid(
        position: Vector3D(x, y, z),
        rotationVelocity: Vector3D(
          (random.nextDouble() - 0.5) * 2,
          (random.nextDouble() - 0.5) * 2,
          (random.nextDouble() - 0.5) * 2,
        ),
        size: 10 + random.nextDouble() * 5,
        color: color,
      );
    });
  }

  void _updateAsteroids() {
    if (!mounted) return;

    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
    final deltaTime = currentTime - lastUpdateTime;
    lastUpdateTime = currentTime;

    for (var asteroid in asteroids) {
      asteroid.update(deltaTime);
    }

    // setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleUpdate: (ScaleUpdateDetails details) {
        setState(() {
          // Update zoom level with constraints
          _zoomLevel = (_zoomLevel * details.scale).clamp(baseDistance / maxDistance, baseDistance / minDistance);
        });
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: AsteroidPainter(
            asteroids: asteroids,
            cameraX: cameraX,
            cameraY: cameraY,
            cameraDistance: cameraDistance,
            fov: fov,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class AsteroidPainter extends CustomPainter {
  final List<Asteroid> asteroids;
  final double cameraX;
  final double cameraY;
  final double cameraDistance;
  final double fov;

  static const double minDistance = 600.0;
  static const double maxDistance = 2000.0;

  AsteroidPainter({
    required this.asteroids,
    required this.cameraX,
    required this.cameraY,
    required this.cameraDistance,
    required this.fov,
  });

  Vector3D getCameraPosition() {
    return Vector3D(cameraDistance * math.sin(cameraX), cameraDistance * math.sin(cameraY),
        cameraDistance * math.cos(cameraX) * math.cos(cameraY));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    final cameraPos = getCameraPosition();
    final viewCenter = const Vector3D(0, 0, 0);

    final forward = (viewCenter - cameraPos).normalized();
    final worldUp = const Vector3D(0, 1, 0);
    final right = forward.cross(worldUp).normalized();
    final up = right.cross(forward).normalized();

    final sortedAsteroids = [...asteroids]..sort((a, b) {
        final aPos = a.position - cameraPos;
        final bPos = b.position - cameraPos;
        return bPos.dot(forward).compareTo(aPos.dot(forward));
      });

    for (var asteroid in sortedAsteroids) {
      final vertices = asteroid.project(cameraPos, forward, right, up, fov);
      if (vertices.isEmpty) continue;

      final path = Path()..addPolygon(vertices, true);

      // Calculate distance-based effects
      final distanceToCamera = (asteroid.position - cameraPos).magnitude;
      final closeness = (1 - (distanceToCamera - minDistance) / (maxDistance - minDistance)).clamp(0.0, 1.0);

      final glowSize = 2 + closeness * 4; // Larger glow when closer
      final glowOpacity = 0.2 + closeness * 0.3; // More intense glow when closer

      // Enhanced outer glow
      canvas.drawPath(
        path,
        Paint()
          ..color = asteroid.color.withOpacity(glowOpacity)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, glowSize),
      );

      // Main shape with distance-based opacity
      canvas.drawPath(
        path,
        Paint()
          ..color = asteroid.color.withOpacity(0.7 + closeness * 0.3)
          ..style = PaintingStyle.fill,
      );

      // Enhanced inner highlight
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.3 + closeness * 0.4)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.inner, 1 + closeness),
      );

      // Add sharp edge highlight when very close
      if (closeness > 0.7) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity((closeness - 0.7) * 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }

      // Add additional small highlight dots at vertices for close shards
      if (closeness > 0.8) {
        for (final vertex in vertices) {
          canvas.drawCircle(
              vertex,
              0.5,
              Paint()
                ..color = Colors.white.withOpacity((closeness - 0.8) * 0.7)
                ..style = PaintingStyle.fill);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(AsteroidPainter oldDelegate) {
    return oldDelegate.cameraX != cameraX ||
        oldDelegate.cameraY != cameraY ||
        oldDelegate.cameraDistance != cameraDistance;
  }
}

void main() {
  runApp(const MaterialApp(
    home: _App(),
  ));
}

class _App extends StatelessWidget {
  const _App({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onScaleStart: (_) {}, // Required for scale updates to work
          child: Stack(
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                child: const AsteroidField(asteroidCount: 40),
              ),
              const AsteroidField(asteroidCount: 20),
            ],
          ),
        ),
      ),
    );
  }
}
