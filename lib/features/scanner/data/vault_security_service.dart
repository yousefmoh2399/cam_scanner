import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/services/local_media_storage_service.dart';
import 'document_search_service.dart';

enum AutoLockTimeout {
  immediate,
  oneMinute,
  fiveMinutes,
  fifteenMinutes;

  String get labelAr => switch (this) {
        AutoLockTimeout.immediate => 'فوراً عند الخروج',
        AutoLockTimeout.oneMinute => 'بعد دقيقة واحدة',
        AutoLockTimeout.fiveMinutes => 'بعد 5 دقائق',
        AutoLockTimeout.fifteenMinutes => 'بعد 15 دقيقة',
      };

  Duration get duration => switch (this) {
        AutoLockTimeout.immediate => Duration.zero,
        AutoLockTimeout.oneMinute => const Duration(minutes: 1),
        AutoLockTimeout.fiveMinutes => const Duration(minutes: 5),
        AutoLockTimeout.fifteenMinutes => const Duration(minutes: 15),
      };
}

class VaultSecuritySettings {
  const VaultSecuritySettings({
    this.appLockEnabled = false,
    this.biometricsEnabled = true,
    this.secureScreenEnabled = false,
    this.autoLockTimeout = AutoLockTimeout.oneMinute,
    this.hasPinConfigured = false,
  });

  final bool appLockEnabled;
  final bool biometricsEnabled;
  final bool secureScreenEnabled;
  final AutoLockTimeout autoLockTimeout;
  final bool hasPinConfigured;

  VaultSecuritySettings copyWith({
    bool? appLockEnabled,
    bool? biometricsEnabled,
    bool? secureScreenEnabled,
    AutoLockTimeout? autoLockTimeout,
    bool? hasPinConfigured,
  }) {
    return VaultSecuritySettings(
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      secureScreenEnabled: secureScreenEnabled ?? this.secureScreenEnabled,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
      hasPinConfigured: hasPinConfigured ?? this.hasPinConfigured,
    );
  }
}

/// Phase 3.3: Offline App Lock (Biometrics + PIN + FLAG_SECURE) & Private Vault
/// with real on-disk AES-256-GCM encryption (`cryptography` + Android Keystore via `FlutterSecureStorage`).
class VaultSecurityService {
  static const MethodChannel _scannerChannel =
      MethodChannel('com.laqta.scanner/scanner');

  static const _keyMasterAes = 'vault_master_aes256_key_v1';
  static const _keyPinHash = 'vault_pin_sha256_hash_v1';
  static const _keyPinSalt = 'vault_pin_salt_v1';
  static const _keyAppLockEnabled = 'security_app_lock_enabled';
  static const _keyBiometricsEnabled = 'security_biometrics_enabled';
  static const _keySecureScreenEnabled = 'security_secure_screen_enabled';
  static const _keyAutoLockTimeout = 'security_auto_lock_timeout';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final LocalAuthentication _localAuth = LocalAuthentication();
  final AesGcm _aesGcm = AesGcm.with256bits();

  Future<VaultSecuritySettings> loadSettings() async {
    try {
      final pinHash = await _secureStorage.read(key: _keyPinHash);
      final appLock =
          (await _secureStorage.read(key: _keyAppLockEnabled)) == 'true';
      final bio =
          (await _secureStorage.read(key: _keyBiometricsEnabled)) != 'false';
      final secureScreen =
          (await _secureStorage.read(key: _keySecureScreenEnabled)) == 'true';
      final timeoutStr = await _secureStorage.read(key: _keyAutoLockTimeout);
      final timeout = AutoLockTimeout.values.firstWhere(
        (e) => e.name == timeoutStr,
        orElse: () => AutoLockTimeout.oneMinute,
      );

      if (secureScreen) {
        await setSecureScreenFlag(true);
      }

      return VaultSecuritySettings(
        appLockEnabled: appLock,
        biometricsEnabled: bio,
        secureScreenEnabled: secureScreen,
        autoLockTimeout: timeout,
        hasPinConfigured: pinHash != null && pinHash.isNotEmpty,
      );
    } catch (e) {
      debugPrint('[VaultSecurityService] loadSettings error: $e');
      return const VaultSecuritySettings();
    }
  }

  Future<void> saveSettings(VaultSecuritySettings settings) async {
    await _secureStorage.write(
      key: _keyAppLockEnabled,
      value: settings.appLockEnabled.toString(),
    );
    await _secureStorage.write(
      key: _keyBiometricsEnabled,
      value: settings.biometricsEnabled.toString(),
    );
    await _secureStorage.write(
      key: _keySecureScreenEnabled,
      value: settings.secureScreenEnabled.toString(),
    );
    await _secureStorage.write(
      key: _keyAutoLockTimeout,
      value: settings.autoLockTimeout.name,
    );
    await setSecureScreenFlag(settings.secureScreenEnabled);
  }

  /// Toggles Android `WindowManager.LayoutParams.FLAG_SECURE` to block screenshots and hide recents preview.
  Future<void> setSecureScreenFlag(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _scannerChannel.invokeMethod('setSecureScreen', {
        'enabled': enabled,
      });
    } catch (e) {
      debugPrint('[VaultSecurityService] setSecureScreenFlag error: $e');
    }
  }

  /// Sets or updates the user's PIN (4-8 digits) and initializes the Android Keystore 256-bit AES master key.
  Future<void> configurePin(String pin) async {
    final clean = pin.trim();
    if (clean.length < 4) {
      throw Exception('يجب أن يتكون الرمز السري من 4 أرقام على الأقل.');
    }
    final saltBytes = SecretKeyData.random(length: 16).bytes;
    final saltB64 = base64Encode(saltBytes);
    final hashB64 = await _hashPin(clean, saltBytes);

    await _secureStorage.write(key: _keyPinSalt, value: saltB64);
    await _secureStorage.write(key: _keyPinHash, value: hashB64);

    // Ensure master AES-256 key is generated and persisted in Keystore
    await _getOrCreateMasterKey();
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _secureStorage.read(key: _keyPinHash);
    final storedSaltB64 = await _secureStorage.read(key: _keyPinSalt);
    if (storedHash == null || storedSaltB64 == null) return false;

    final saltBytes = base64Decode(storedSaltB64);
    final computedHash = await _hashPin(pin.trim(), saltBytes);
    return computedHash == storedHash;
  }

  Future<String> _hashPin(String pin, List<int> salt) async {
    final sha256 = Sha256();
    final input = <int>[...salt, ...utf8.encode(pin), ...salt];
    final hash = await sha256.hash(input);
    return base64Encode(hash.bytes);
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics({
    String reason = 'الرجاء تأكيد هويتك لفتح المستندات المحمية',
  }) async {
    try {
      final available = await canCheckBiometrics();
      if (!available) return false;
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[VaultSecurityService] Biometric auth error: $e');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // AES-256-GCM On-Disk Encryption Engine
  // ───────────────────────────────────────────────────────────────────────────

  Future<SecretKey> _getOrCreateMasterKey() async {
    final existingB64 = await _secureStorage.read(key: _keyMasterAes);
    if (existingB64 != null && existingB64.isNotEmpty) {
      return SecretKey(base64Decode(existingB64));
    }
    final newKeyData = SecretKeyData.random(length: 32); // 256 bits
    await _secureStorage.write(
      key: _keyMasterAes,
      value: base64Encode(newKeyData.bytes),
    );
    return newKeyData;
  }

  /// Encrypts raw bytes using AES-256-GCM.
  /// Wire format: `[12-byte nonce][ciphertext][16-byte GCM MAC tag]`.
  Future<Uint8List> encryptBytes(
    Uint8List plainBytes, {
    SecretKey? customKey,
  }) async {
    final secretKey = customKey ?? await _getOrCreateMasterKey();
    final nonce = _aesGcm.newNonce(); // 12 bytes
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    return secretBox.concatenation();
  }

  /// Decrypts an AES-256-GCM concatenated payload (`[12-byte nonce][ciphertext][16-byte MAC]`).
  Future<Uint8List> decryptBytes(
    Uint8List encryptedBytes, {
    SecretKey? customKey,
  }) async {
    if (encryptedBytes.length < 28) {
      throw Exception('البيانات المشفرة غير صالحة أو تالفة.');
    }
    final secretKey = customKey ?? await _getOrCreateMasterKey();
    final secretBox = SecretBox.fromConcatenation(
      encryptedBytes,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(clear);
  }

  /// Derives a 256-bit AES key from a user password (used for encrypted Backup ZIP).
  Future<SecretKey> deriveKeyFromPassword(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 15000,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Secret Vault Storage Management
  // ───────────────────────────────────────────────────────────────────────────

  Future<Directory> _vaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'secret_vault'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _vaultIndexFile() async {
    final dir = await _vaultDirectory();
    return File(p.join(dir.path, 'vault_index.enc'));
  }

  /// Loads and decrypts all documents currently stored in the Secret Vault.
  Future<List<PendingUpload>> loadVaultDocuments() async {
    try {
      final indexFile = await _vaultIndexFile();
      if (!await indexFile.exists()) return const [];
      final encBytes = await indexFile.readAsBytes();
      if (encBytes.isEmpty) return const [];

      final clearBytes = await decryptBytes(encBytes);
      final jsonList =
          jsonDecode(utf8.decode(clearBytes)) as List<dynamic>? ?? const [];
      return jsonList
          .whereType<Map<String, dynamic>>()
          .map(PendingUpload.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[VaultSecurityService] loadVaultDocuments error: $e');
      return const [];
    }
  }

  Future<void> saveVaultDocuments(List<PendingUpload> docs) async {
    final indexFile = await _vaultIndexFile();
    final rawJson = utf8.encode(
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
    final encBytes = await encryptBytes(Uint8List.fromList(rawJson));
    await indexFile.writeAsBytes(encBytes, flush: true);
  }

  /// Encrypts all files belonging to [document] on disk with AES-256-GCM,
  /// stores the encrypted record in the Secret Vault, deletes the plaintext files,
  /// and removes the document from SQLite FTS search index.
  Future<void> moveDocumentToVault(PendingUpload document) async {
    final vaultDir = await _vaultDirectory();
    final filesDir = Directory(p.join(vaultDir.path, 'files'));
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }

    Future<String> encryptFileAndRemoveOriginal(
      String originalPath,
      String suffix,
    ) async {
      if (originalPath.isEmpty) return '';
      final src = File(originalPath);
      if (!await src.exists()) return '';

      final plainBytes = await src.readAsBytes();
      final encBytes = await encryptBytes(plainBytes);
      final encPath = p.join(
        filesDir.path,
        '${document.id}_${suffix}_${p.basename(originalPath)}.enc',
      );
      await File(encPath).writeAsBytes(encBytes, flush: true);
      try {
        await src.delete();
      } catch (_) {}
      return encPath;
    }

    final encPdfPath = await encryptFileAndRemoveOriginal(
      document.filePath,
      'pdf',
    );
    final encThumbPath = document.thumbnailPath != null
        ? await encryptFileAndRemoveOriginal(document.thumbnailPath!, 'thumb')
        : null;

    final encPages = <ScannedPage>[];
    for (var i = 0; i < document.pages.length; i++) {
      final pg = document.pages[i];
      final encImg = await encryptFileAndRemoveOriginal(
        pg.imagePath,
        'page_$i',
      );
      final encOrig = pg.originalImagePath != null &&
              pg.originalImagePath != pg.imagePath
          ? await encryptFileAndRemoveOriginal(
              pg.originalImagePath!,
              'orig_$i',
            )
          : encImg;
      encPages.add(
        pg.copyWith(
          imagePath: encImg,
          originalImagePath: encOrig,
        ),
      );
    }

    final vaultDoc = document.copyWith(
      filePath: encPdfPath,
      thumbnailPath: encThumbPath,
      pages: encPages,
    );

    final current = await loadVaultDocuments();
    final updated = <PendingUpload>[
      vaultDoc,
      ...current.where((d) => d.id != document.id),
    ];
    await saveVaultDocuments(updated);

    // Remove from SQLite Full-Text Search Index so it cannot be discovered via search
    await DocumentSearchService().removeDocument(document.id);
  }

  /// Decrypts a document from the Secret Vault back to plaintext storage and returns the restored [PendingUpload].
  Future<PendingUpload> restoreDocumentFromVault(String documentId) async {
    final current = await loadVaultDocuments();
    final target = current.firstWhere(
      (d) => d.id == documentId,
      orElse: () => throw Exception('المستند غير موجود في الخزنة السرية.'),
    );

    const mediaStorage = LocalMediaStorageService();
    final docsDir = await mediaStorage.documentsDirectory();
    final pagesDir = await mediaStorage.pagesDirectory();

    Future<String> decryptFileTo(
      String encPath,
      Directory destDir,
    ) async {
      if (encPath.isEmpty) return '';
      final encFile = File(encPath);
      if (!await encFile.exists()) return '';

      final encBytes = await encFile.readAsBytes();
      final clearBytes = await decryptBytes(encBytes);
      var origName = p.basename(encPath);
      if (origName.endsWith('.enc')) {
        origName = origName.substring(0, origName.length - 4);
      }
      final destPath = p.join(destDir.path, origName);
      await File(destPath).writeAsBytes(clearBytes, flush: true);
      try {
        await encFile.delete();
      } catch (_) {}
      return destPath;
    }

    final clearPdfPath = await decryptFileTo(target.filePath, docsDir);
    final clearThumbPath = target.thumbnailPath != null
        ? await decryptFileTo(target.thumbnailPath!, pagesDir)
        : null;

    final clearPages = <ScannedPage>[];
    for (final pg in target.pages) {
      final clearImg = await decryptFileTo(pg.imagePath, pagesDir);
      final clearOrig = pg.originalImagePath != null &&
              pg.originalImagePath != pg.imagePath
          ? await decryptFileTo(pg.originalImagePath!, pagesDir)
          : clearImg;
      clearPages.add(
        pg.copyWith(
          imagePath: clearImg,
          originalImagePath: clearOrig,
        ),
      );
    }

    final restored = target.copyWith(
      filePath: clearPdfPath,
      thumbnailPath: clearThumbPath,
      pages: clearPages,
    );

    final remaining = current.where((d) => d.id != documentId).toList();
    await saveVaultDocuments(remaining);

    return restored;
  }

  /// Decrypts a single page/PDF temporarily into memory (`Uint8List`) for viewing inside the Vault without writing plaintext to public storage.
  Future<Uint8List?> decryptFileToMemory(String encryptedFilePath) async {
    if (encryptedFilePath.isEmpty) return null;
    final file = File(encryptedFilePath);
    if (!await file.exists()) return null;
    final encBytes = await file.readAsBytes();
    return decryptBytes(encBytes);
  }

  /// Deletes a document permanently from the Secret Vault.
  Future<void> deleteFromVaultPermanently(String documentId) async {
    final current = await loadVaultDocuments();
    final target = current.where((d) => d.id == documentId).firstOrNull;
    if (target != null) {
      for (final path in <String?>[
        target.filePath,
        target.thumbnailPath,
        ...target.pages.map((p) => p.imagePath),
        ...target.pages.map((p) => p.originalImagePath),
      ]) {
        if (path != null && path.isNotEmpty) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    }
    final remaining = current.where((d) => d.id != documentId).toList();
    await saveVaultDocuments(remaining);
  }
}
