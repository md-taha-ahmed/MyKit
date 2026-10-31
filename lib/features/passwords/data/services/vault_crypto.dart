import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../../core/i18n/i18n.dart';

class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Argon2id settings stored with the vault, so they can be raised later
/// without breaking existing vaults.
class KdfParams {
  const KdfParams({
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  /// OWASP's minimum recommendation for Argon2id: 19 MiB, 2 passes.
  static const recommended = KdfParams();

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'alg': 'argon2id',
    'm': memoryKiB,
    't': iterations,
    'p': parallelism,
  };

  static KdfParams fromJson(Map<String, dynamic> j) {
    if (j['alg'] != 'argon2id') {
      throw VaultException(tr('Unknown vault format.'));
    }
    return KdfParams(
      memoryKiB: (j['m'] as num).toInt(),
      iterations: (j['t'] as num).toInt(),
      parallelism: (j['p'] as num).toInt(),
    );
  }
}

/// The encrypted vault as stored (in preferences, and so in Drive backups):
///
/// * a random 256-bit **vault key** encrypts the entries (AES-256-GCM);
/// * the vault key is itself encrypted with a key derived from the master
///   password (Argon2id + random salt).
///
/// Changing the master password only re-wraps the vault key. Nothing in
/// here is readable without the master password (or, on this phone only, the
/// fingerprint-protected copy of the vault key).
class SealedVault {
  const SealedVault({
    required this.kdf,
    required this.salt,
    required this.wrappedKey,
    required this.data,
  });

  static const version = 1;

  final KdfParams kdf;
  final List<int> salt;

  /// The vault key, encrypted with the master-password key.
  final SecretBox wrappedKey;

  /// The entries (JSON), encrypted with the vault key.
  final SecretBox data;

  String encode() => jsonEncode({
    'v': version,
    'kdf': {...kdf.toJson(), 'salt': base64Encode(salt)},
    'key': _box(wrappedKey),
    'data': _box(data),
  });

  static SealedVault decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if ((j['v'] as num) > version) {
        throw VaultException(tr('This vault is from a newer MyKit.'));
      }
      final kdf = j['kdf'] as Map<String, dynamic>;
      return SealedVault(
        kdf: KdfParams.fromJson(kdf),
        salt: base64Decode(kdf['salt'] as String),
        wrappedKey: _unbox(j['key'] as Map<String, dynamic>),
        data: _unbox(j['data'] as Map<String, dynamic>),
      );
    } on VaultException {
      rethrow;
    } catch (_) {
      throw VaultException(tr('The saved vault is damaged.'));
    }
  }

  static Map<String, String> _box(SecretBox b) => {
    'n': base64Encode(b.nonce),
    'c': base64Encode(b.cipherText),
    'm': base64Encode(b.mac.bytes),
  };

  static SecretBox _unbox(Map<String, dynamic> j) => SecretBox(
    base64Decode(j['c'] as String),
    nonce: base64Decode(j['n'] as String),
    mac: Mac(base64Decode(j['m'] as String)),
  );
}

/// Encryption for the Passwords vault.
abstract final class VaultCrypto {
  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  /// Binds ciphertexts to their purpose (a wrapped key can't be swapped in
  /// as data and vice versa).
  static final _keyAad = utf8.encode('mykit-vault-v1:key');
  static final _dataAad = utf8.encode('mykit-vault-v1:data');

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// A new random vault key.
  static Uint8List newVaultKey() => randomBytes(32);

  /// Master password → 256-bit key. Argon2id is deliberately slow and
  /// memory-hungry, so it runs on a background isolate.
  static Future<Uint8List> deriveKey(
    String password,
    List<int> salt,
    KdfParams params,
  ) {
    final passwordBytes = utf8.encode(password);
    return Isolate.run(() async {
      final key = await Argon2id(
        parallelism: params.parallelism,
        memory: params.memoryKiB,
        iterations: params.iterations,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(passwordBytes), nonce: salt);
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  /// Seals [entriesJson] under [vaultKey], wrapping the key with [kek] (the
  /// master-password key).
  static Future<SealedVault> seal({
    required Uint8List vaultKey,
    required Uint8List kek,
    required List<int> salt,
    required KdfParams kdf,
    required String entriesJson,
    SecretBox? wrappedKey,
  }) async {
    final wrapped =
        wrappedKey ??
        await _aes.encrypt(vaultKey, secretKey: SecretKey(kek), aad: _keyAad);
    final data = await _aes.encrypt(
      utf8.encode(entriesJson),
      secretKey: SecretKey(vaultKey),
      aad: _dataAad,
    );
    return SealedVault(kdf: kdf, salt: salt, wrappedKey: wrapped, data: data);
  }

  /// Re-encrypts the entries with the same vault key and wrapping.
  static Future<SealedVault> reseal(
    SealedVault vault,
    Uint8List vaultKey,
    String entriesJson,
  ) async => SealedVault(
    kdf: vault.kdf,
    salt: vault.salt,
    wrappedKey: vault.wrappedKey,
    data: await _aes.encrypt(
      utf8.encode(entriesJson),
      secretKey: SecretKey(vaultKey),
      aad: _dataAad,
    ),
  );

  /// The vault key, if [kek] is right. Throws [VaultException] otherwise.
  static Future<Uint8List> unwrapKey(SealedVault vault, Uint8List kek) async {
    try {
      return Uint8List.fromList(
        await _aes.decrypt(
          vault.wrappedKey,
          secretKey: SecretKey(kek),
          aad: _keyAad,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw VaultException(tr('Wrong master password.'));
    }
  }

  /// The entries JSON. Throws [VaultException] if [vaultKey] doesn't fit.
  static Future<String> open(SealedVault vault, Uint8List vaultKey) async {
    try {
      return utf8.decode(
        await _aes.decrypt(
          vault.data,
          secretKey: SecretKey(vaultKey),
          aad: _dataAad,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw VaultException(tr('Could not open the vault.'));
    }
  }
}
