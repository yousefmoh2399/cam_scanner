import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Motion Tokens for CamScanner RTL (Offline)
///
/// Built according to Apple WWDC Fluid Interfaces, Emil Kowalski's Design
/// Engineering motion philosophy, and strict Animation Performance standards.
///
/// Sources:
/// - `animate/SKILL.md` (Duration thresholds, composite-only rules, custom curves)
/// - `apple-design/SKILL.md` (Spring physics: Damping 1.0 / 0.8, Response 0.3-0.4, velocity handoff)
/// - `emil-design-eng/SKILL.md` (scale 0.97 on press, custom bezier values, <300ms UI limit)
/// - `animation-performance/SKILL.md` (Blur limits ≤20px, frame budget ≤8ms on 120Hz)
/// - `animation-vocabulary/SKILL.md` (Exact terminology: Press feedback, Pop in, Stagger, Rubber-banding)
abstract final class MotionTokens {
  // ─── 1. DURATIONS (Under 300ms for UI snappiness) ──────────────────────────

  /// [Press feedback] (100–160ms) — Emil / Apple
  /// Fast instant response confirming the interface heard the user.
  static const Duration pressFeedback = Duration(milliseconds: 120);

  /// [Press delay] (40–80ms, tuned to 50ms)
  /// Crucial delay before initiating press scale down.
  /// Rationale: Allows fast scrolling/flings to move past [kTouchSlop] before
  /// shrinking the card, preventing distracting micro-shrink flashes during scrolling.
  static const Duration pressFeedbackDelay = Duration(milliseconds: 50);

  /// [Pop in / Filter Selection] (150–200ms)
  /// Used for small chips, segmented selectors, and tooltips.
  static const Duration chipSelection = Duration(milliseconds: 160);

  /// [Standard UI Transition] (180–250ms)
  /// Standard duration for state changes, tabs, and small toggles.
  static const Duration standard = Duration(milliseconds: 200);

  /// [Modal / Sheet Enter] (250–280ms)
  /// Entrance duration for bottom sheets and floating dialogs.
  static const Duration sheetEnter = Duration(milliseconds: 280);

  /// [Modal / Sheet Exit] (180–200ms)
  /// Asymmetric timing: Exit is faster than enter to feel responsive on dismissal.
  static const Duration sheetExit = Duration(milliseconds: 200);

  /// [Stagger Delay] (30–50ms) — Emil / animate
  /// Cascade delay between sequentially entering items.
  static const Duration staggerDelay = Duration(milliseconds: 40);

  // ─── 2. EASING CURVES (Custom cubic-beziers from tables) ───────────────────

  /// Strong ease-out curve for UI entrances, tabs, and feedbacks.
  /// Source: `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)` (Emil & animate)
  static const Curve easeOutStrong = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Strong ease-in-out curve for moving elements already on screen.
  /// Source: `--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1)` (Emil & animate)
  static const Curve easeInOutStrong = Cubic(0.77, 0.0, 0.175, 1.0);

  /// iOS-like drawer curve for bottom sheets and sliding surfaces.
  /// Source: `--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1)` (Ionic / Apple)
  static const Curve drawerCurve = Cubic(0.32, 0.72, 0.0, 1.0);

  // ─── 3. SPRING DESCRIPTIONS (Apple WWDC Fluid Interfaces) ──────────────────

  /// [Critically Damped Spring] (Damping 1.0, Response ~0.3s)
  /// Default for UI elements, cards, and modal sheets. Zero unwanted bounce.
  /// Settles cleanly and maintains interruptibility.
  static const SpringDescription springSnappy = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 34.64, // 2 * sqrt(300) => damping ratio = 1.0 (critically damped)
  );

  /// [Standard Reposition Spring] (Damping 1.0, Response ~0.4s)
  /// Apple move/reposition default.
  static const SpringDescription springStandard = SpringDescription(
    mass: 1.0,
    stiffness: 220.0,
    damping: 29.66, // 2 * sqrt(220) => damping ratio = 1.0
  );

  /// [Momentum / Flick Spring] (Damping ~0.8, Response ~0.35s)
  /// Slight playful bounce. Used ONLY when preceded by physical flick/momentum.
  static const SpringDescription springBouncy = SpringDescription(
    mass: 1.0,
    stiffness: 260.0,
    damping: 25.79, // damping ratio ≈ 0.8
  );

  // ─── 4. SCALE TOKENS (Never scale(0)) ──────────────────────────────────────

  /// Standard button/card press scale feedback.
  /// Source: `emil-design-eng` (transform: scale(0.97))
  static const double pressScale = 0.97;

  /// Subtle press scale for large cards or list items.
  static const double pressScaleSubtle = 0.985;

  /// Entry start scale (combined with opacity 0).
  /// Source: `animate` §4 (Never scale(0); start from 0.95)
  static const double entryStartScale = 0.95;

  // ─── 5. BLUR / MATERIAL CEILINGS (animation-performance) ───────────────────

  /// Recommended soft blur for glass/frost surfaces on mobile.
  static const double blurSubtle = 5.0;

  /// Upper standard threshold for fluid UI components.
  static const double blurStandard = 10.0;

  /// Strict maximum recommended blur radius for animated or scrolling layers.
  /// Source: `animation-performance/SKILL.md` ("Keep animated blur under 20px").
  static const double blurMaxRecommended = 20.0;

  // AUDIT WARNINGS:
  // 1. [apple_bottom_nav_bar.dart:118] uses sigma 25, which EXCEEDS blurMaxRecommended.
  // 2. [library_screen.dart:3505] uses sigma 10 inside EVERY document thumbnail card.
  //    This creates multiple active blur shaders during fast scrolling and should be
  //    guarded or replaced with high-contrast semi-transparent solid tinting.

  // ─── 6. ACCESSIBILITY & HELPERS (prefers-reduced-motion) ────────────────────

  /// Respects `MediaQuery.disableAnimationsOf`.
  /// Returns [Duration.zero] if the user requested reduced motion.
  static Duration getDuration(BuildContext context, Duration normal) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Duration.zero;
    }
    return normal;
  }

  /// Builds an [AnimationStyle] for [showModalBottomSheet] adhering to Apple curves
  /// and respecting reduced-motion accessibility.
  static AnimationStyle sheetAnimationStyle(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimationStyle.noAnimation;
    }
    return const AnimationStyle(
      curve: drawerCurve,
      duration: sheetEnter,
      reverseDuration: sheetExit,
    );
  }
}

/// A touch feedback wrapper that uses [Listener] (raw pointer events)
/// with touch-slop and drag cancellation to eliminate gesture arena conflict with
/// [LongPressDraggable] or scrolling containers.
///
/// Architectural guarantees:
/// 1. Slop detection: If pointer moves more than [kTouchSlop] (18dp), scale resets to 1.0.
/// 2. Press delay (50ms): Cancels timer if finger moves before 50ms (avoids scroll jitter).
/// 3. Explicit drag cancellation: [reset] can be called directly by [LongPressDraggable.onDragStarted].
/// 4. Up/Cancel safety: Resets scale on [PointerUpEvent] and [PointerCancelEvent].
class RawPressFeedback extends StatefulWidget {
  const RawPressFeedback({
    super.key,
    required this.child,
    this.targetScale = MotionTokens.pressScale,
    this.duration = MotionTokens.pressFeedback,
    this.pressDelay = MotionTokens.pressFeedbackDelay,
    this.curve = MotionTokens.easeOutStrong,
  });

  final Widget child;
  final double targetScale;
  final Duration duration;
  final Duration pressDelay;
  final Curve curve;

  @override
  State<RawPressFeedback> createState() => RawPressFeedbackState();
}

class RawPressFeedbackState extends State<RawPressFeedback> {
  bool _isPressed = false;
  Offset? _downPosition;
  Timer? _pressTimer;

  /// Explicitly resets scale back to 1.0 (e.g. called from onDragStarted).
  void reset() {
    _pressTimer?.cancel();
    _pressTimer = null;
    _downPosition = null;
    if (_isPressed && mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.position;
    _pressTimer?.cancel();
    _pressTimer = Timer(widget.pressDelay, () {
      if (mounted && _downPosition != null) {
        setState(() => _isPressed = true);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_downPosition != null) {
      final delta = (event.position - _downPosition!).distance;
      if (delta > kTouchSlop) {
        // Pointer moved beyond slop threshold (user is scrolling)
        reset();
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    reset();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    reset();
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = MotionTokens.getDuration(context, widget.duration);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedScale(
        scale: _isPressed ? widget.targetScale : 1.0,
        duration: effectiveDuration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}
