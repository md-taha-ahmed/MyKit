import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/passwords/data/services/vault_crypto.dart';
import 'package:mykit/features/passwords/domain/services/password_tools.dart';
import 'package:mykit/features/passwords/domain/services/vault_csv.dart';
import 'package:mykit/features/passwords/presentation/providers/vault_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('crypto', () {
    test('seal → unwrap with the right password → open', () async {
      final salt = VaultCrypto.randomBytes(16);
      const kdf = KdfParams.recommended;
      final kek = await VaultCrypto.deriveKey('correct horse', salt, kdf);
      final vaultKey = VaultCrypto.newVaultKey();
      final sealed = await VaultCrypto.seal(
        vaultKey: vaultKey,
        kek: kek,
        salt: salt,
        kdf: kdf,
        entriesJson: '[{"id":"1"}]',
      );
      final restored = SealedVault.decode(sealed.encode());
      expect(sealed.encode(), isNot(contains('"id"')));

      final again = await VaultCrypto.deriveKey('correct horse', salt, kdf);
      final key = await VaultCrypto.unwrapKey(restored, again);
      expect(await VaultCrypto.open(restored, key), '[{"id":"1"}]');

      final wrong = await VaultCrypto.deriveKey('wrong horse', salt, kdf);
      await expectLater(
        VaultCrypto.unwrapKey(restored, wrong),
        throwsA(isA<VaultException>()),
      );
    });

    test('tampered data is rejected', () async {
      final salt = VaultCrypto.randomBytes(16);
      final kek = await VaultCrypto.deriveKey(
        'pw',
        salt,
        KdfParams.recommended,
      );
      final vaultKey = VaultCrypto.newVaultKey();
      final sealed = await VaultCrypto.seal(
        vaultKey: vaultKey,
        kek: kek,
        salt: salt,
        kdf: KdfParams.recommended,
        entriesJson: '[]',
      );
      final raw = sealed.encode().replaceFirstMapped(
        RegExp(r'"data":\{"n":"([^"]+)","c":"(.)'),
        (m) => '"data":{"n":"${m[1]}","c":"${m[2] == 'A' ? 'B' : 'A'}',
      );
      await expectLater(
        VaultCrypto.open(SealedVault.decode(raw), vaultKey),
        throwsA(isA<VaultException>()),
      );
    });
  });

  group('csv', () {
    test('Chrome export, quotes and line breaks', () {
      const csv =
          'name,url,username,password,note\r\n'
          'GitHub,https://github.com/login,me@x.com,"p,a""ss",\r\n'
          ',https://www.bank.com,acct,secret,"line 1\nline 2"\r\n'
          'Empty,https://x.com,u,,\r\n';
      final logins = VaultCsv.parse(csv);
      expect(logins.length, 2);
      expect(logins[0].password, 'p,a"ss');
      expect(logins[1].title, 'bank.com');
      expect(logins[1].notes, 'line 1\nline 2');
    });

    test('Bitwarden and KeePass headers', () {
      final bw = VaultCsv.parse(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        ',,login,Mail,,,0,https://mail.com,me,pw1,\n',
      );
      expect(
        (bw.single.title, bw.single.url, bw.single.password),
        ('Mail', 'https://mail.com', 'pw1'),
      );
      final kp = VaultCsv.parse(
        '"Group","Title","Username","Password","URL","Notes"\n'
        '"Root","Shop","bob","pw2","shop.com",""\n',
      );
      expect((kp.single.title, kp.single.username), ('Shop', 'bob'));
    });

    test('no password column is a clear error', () {
      expect(
        () => VaultCsv.parse('a,b\n1,2\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('generator: length, every group, no look-alikes', () {
    for (var i = 0; i < 50; i++) {
      final p = generatePassword(const GeneratorOptions(length: 16));
      expect(p.length, 16);
      expect(p, matches(RegExp('[A-Z]')));
      expect(p, matches(RegExp('[a-z]')));
      expect(p, matches(RegExp('[0-9]')));
      expect(p, matches(RegExp(r'[^A-Za-z0-9]')));
      expect(p, isNot(matches(RegExp('[O0oIl1|]'))));
    }
    expect(strengthOf('password'), PasswordStrength.veryWeak);
    expect(strengthOf('summer2024'), PasswordStrength.fair);
    expect(
      strengthOf(generatePassword(const GeneratorOptions())),
      PasswordStrength.veryStrong,
    );
  });

  test('vault: create, add, lock, unlock, import without duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final vault = container.read(vaultProvider.notifier);

    await vault.create('a long master password');
    await vault.add(
      title: 'GitHub',
      username: 'me',
      password: 'pw-1',
      url: 'github.com',
    );
    expect(prefs.getString('vault.v1'), isNot(contains('pw-1')));

    vault.lock();
    expect(container.read(vaultProvider).entries, isEmpty);
    await expectLater(
      vault.unlockWithPassword('nope'),
      throwsA(isA<VaultException>()),
    );
    await vault.unlockWithPassword('a long master password');
    expect(container.read(vaultProvider).entries.single.title, 'GitHub');

    final (added, skipped) = await vault.importCsv(
      'name,url,username,password\n'
      'GitHub,https://www.github.com/login,me,pw-1\n'
      'Bank,bank.com,me,pw-2\n',
    );
    expect((added, skipped), (1, 1));
    expect(VaultCsv.parse(vault.exportCsv()).length, 2);

    await vault.changeMasterPassword('a long master password', 'another one!!');
    vault.lock();
    await vault.unlockWithPassword('another one!!');
    expect(container.read(vaultProvider).entries.length, 2);
  });
}
