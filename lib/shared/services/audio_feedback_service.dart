import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioFeedbackServiceProvider = Provider<AudioFeedbackService>((ref) {
  final service = AudioFeedbackService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// خدمة التفاعلات الصوتية الخفيفة (Audio Cues & Haptic Sensory Feedback)
/// - توليد نغمات ونقرات ميكانيكية دقيقة في الذاكرة بدون الحاجة لتحميل ملفات خارجية (100% Offline)
/// - مدمجة بتناغم مع الاهتزازات الحسية (Apple Haptics) لشعور واقعي ممتع
class AudioFeedbackService {
  AudioFeedbackService() {
    _initAudioPlayer();
  }

  AudioPlayer? _player;
  bool isMuted = false;

  // Cached synthesized WAV bytes
  Uint8List? _shutterBytes;
  Uint8List? _stampBytes;
  Uint8List? _vaultLockBytes;
  Uint8List? _vaultUnlockBytes;
  Uint8List? _successBytes;
  Uint8List? _clickBytes;

  void _initAudioPlayer() {
    try {
      _player = AudioPlayer();
      _player?.setReleaseMode(ReleaseMode.stop);
      _player?.setVolume(0.45); // Subtle, comfortable tactile volume
    } catch (e) {
      debugPrint('[AudioFeedbackService] Player init warning: $e');
    }
  }

  /// نغمة التقاط الكاميرا والمسح الضوئي (Camera Shutter Click)
  Future<void> playShutter() async {
    await HapticFeedback.mediumImpact();
    if (isMuted) return;
    _shutterBytes ??= _generateShutterWav();
    await _playBytes(_shutterBytes!);
  }

  /// صوت ختم المستند الورقي الحقيقي (Paper Stamp / Ink Impression Thud)
  Future<void> playStamp() async {
    await HapticFeedback.heavyImpact();
    if (isMuted) return;
    _stampBytes ??= _generateStampWav();
    await _playBytes(_stampBytes!);
  }

  /// صوت إغلاق وقفل الخزنة الميكانيكية المشفرة (Vault Lock)
  Future<void> playVaultLock() async {
    await HapticFeedback.heavyImpact();
    if (isMuted) return;
    _vaultLockBytes ??= _generateVaultLockWav();
    await _playBytes(_vaultLockBytes!);
  }

  /// صوت فتح وترحيب الخزنة السرية (Vault Unlock Harmony)
  Future<void> playVaultUnlock() async {
    await HapticFeedback.mediumImpact();
    if (isMuted) return;
    _vaultUnlockBytes ??= _generateVaultUnlockWav();
    await _playBytes(_vaultUnlockBytes!);
  }

  /// نغمة إنجاز وتأكيد العملية بنجاح (Success Chime)
  Future<void> playSuccess() async {
    await HapticFeedback.lightImpact();
    if (isMuted) return;
    _successBytes ??= _generateSuccessWav();
    await _playBytes(_successBytes!);
  }

  /// نقرة لمسية رقيقة للقوائم والأزرار (Selection Click)
  Future<void> playClick() async {
    await HapticFeedback.selectionClick();
    if (isMuted) return;
    _clickBytes ??= _generateClickWav();
    await _playBytes(_clickBytes!);
  }

  Future<void> _playBytes(Uint8List bytes) async {
    try {
      if (_player == null) {
        _initAudioPlayer();
      }
      await _player?.stop();
      await _player?.play(BytesSource(bytes));
    } catch (_) {
      // Fallback to system click if sound synthesis unavailable
      await SystemSound.play(SystemSoundType.click);
    }
  }

  void dispose() {
    try {
      _player?.dispose();
      _player = null;
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // Synthesizers: Generates pure 16-bit mono PCM WAV bytes in-memory
  // ─────────────────────────────────────────────────────────────

  static Uint8List _buildWav(int sampleRate, List<int> samples) {
    final byteData = ByteData(44 + samples.length * 2);
    // RIFF header
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F
    byteData.setUint32(4, 36 + samples.length * 2, Endian.little);
    // WAVE
    byteData.setUint8(8, 0x57);  // W
    byteData.setUint8(9, 0x41);  // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E
    // fmt subchunk
    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6D); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    byteData.setUint16(32, 2, Endian.little);  // BlockAlign
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample
    // data subchunk
    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a
    byteData.setUint32(40, samples.length * 2, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      byteData.setInt16(44 + i * 2, samples[i].clamp(-32768, 32767), Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  /// Shutter: Quick double click snap (~45ms)
  static Uint8List _generateShutterWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.045).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // Dual mechanical impulse
      final env1 = math.exp(-t * 220);
      final env2 = (t > 0.012) ? math.exp(-(t - 0.012) * 260) : 0.0;
      final wave1 = math.sin(2 * math.pi * 1800 * t);
      final wave2 = math.sin(2 * math.pi * 950 * t);
      final sample = (wave1 * env1 * 18000) + (wave2 * env2 * 22000);
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }

  /// Stamp: Punchy low thud with paper friction (~60ms)
  static Uint8List _generateStampWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.060).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // Exponential envelope decay
      final env = math.exp(-t * 75);
      // Low punchy frequency falling from 120Hz to 65Hz
      final freq = 120 - (t * 800).clamp(0, 55);
      final wave = math.sin(2 * math.pi * freq * t);
      // Subtle high-frequency contact snap in the first 4ms
      final snap = (t < 0.005) ? math.sin(2 * math.pi * 2200 * t) * 0.35 : 0.0;
      final sample = (wave + snap) * env * 26000;
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }

  /// Vault Lock: Metallic double bolt click (~80ms)
  static Uint8List _generateVaultLockWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.080).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final env1 = math.exp(-t * 110);
      final env2 = (t > 0.025) ? math.exp(-(t - 0.025) * 140) : 0.0;
      final bolt1 = math.sin(2 * math.pi * 240 * t) + 0.3 * math.sin(2 * math.pi * 720 * t);
      final bolt2 = math.sin(2 * math.pi * 160 * t) + 0.4 * math.sin(2 * math.pi * 480 * t);
      final sample = (bolt1 * env1 * 17000) + (bolt2 * env2 * 21000);
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }

  /// Vault Unlock: Harmonic ascending chime (~95ms)
  static Uint8List _generateVaultUnlockWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.095).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final env1 = math.exp(-t * 40);
      final env2 = (t > 0.035) ? math.exp(-(t - 0.035) * 45) : 0.0;
      final tone1 = math.sin(2 * math.pi * 587.33 * t); // D5
      final tone2 = math.sin(2 * math.pi * 880.00 * t); // A5
      final sample = (tone1 * env1 * 14000) + (tone2 * env2 * 18000);
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }

  /// Success: Gentle luxury triad chime (~110ms)
  static Uint8List _generateSuccessWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.110).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final env1 = math.exp(-t * 30);
      final env2 = (t > 0.030) ? math.exp(-(t - 0.030) * 35) : 0.0;
      final env3 = (t > 0.060) ? math.exp(-(t - 0.060) * 40) : 0.0;
      final c5 = math.sin(2 * math.pi * 523.25 * t);
      final e5 = math.sin(2 * math.pi * 659.25 * t);
      final g5 = math.sin(2 * math.pi * 783.99 * t);
      final sample = (c5 * env1 * 10000) + (e5 * env2 * 12000) + (g5 * env3 * 15000);
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }

  /// Subtle Selection Click (~12ms)
  static Uint8List _generateClickWav() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.012).round();
    final samples = List<int>.filled(totalSamples, 0);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 400);
      final wave = math.sin(2 * math.pi * 1400 * t);
      final sample = wave * env * 16000;
      samples[i] = sample.round();
    }
    return _buildWav(sampleRate, samples);
  }
}
