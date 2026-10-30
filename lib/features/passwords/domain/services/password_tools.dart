import 'dart:math';

/// Options for [generatePassword].
class GeneratorOptions {
  const GeneratorOptions({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = true,
  });

  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;

  /// Leave out look-alikes (0/O, 1/l/I) so it's easy to type by hand.
  final bool avoidAmbiguous;

  GeneratorOptions copyWith({
    int? length,
    bool? upper,
    bool? lower,
    bool? digits,
    bool? symbols,
    bool? avoidAmbiguous,
  }) => GeneratorOptions(
    length: length ?? this.length,
    upper: upper ?? this.upper,
    lower: lower ?? this.lower,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
  );
}

const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _lower = 'abcdefghijklmnopqrstuvwxyz';
const _digits = '0123456789';
const _symbols = r'!@#$%^&*()-_=+[]{};:,.?/~';
const _ambiguous = 'O0oIl1|';

/// A random password using a cryptographically secure generator, with at
/// least one character from each chosen group.
String generatePassword(GeneratorOptions o, {Random? random}) {
  final rnd = random ?? Random.secure();
  String clean(String set) => o.avoidAmbiguous
      ? set.split('').where((c) => !_ambiguous.contains(c)).join()
      : set;
  final groups = [
    if (o.upper) clean(_upper),
    if (o.lower) clean(_lower),
    if (o.digits) clean(_digits),
    if (o.symbols) _symbols,
  ];
  if (groups.isEmpty) groups.add(clean(_lower));
  final all = groups.join();
  final length = max(o.length, groups.length);

  final chars = [
    for (final g in groups) g[rnd.nextInt(g.length)],
    for (var i = groups.length; i < length; i++) all[rnd.nextInt(all.length)],
  ]..shuffle(rnd);
  return chars.join();
}

enum PasswordStrength { veryWeak, weak, fair, strong, veryStrong }

extension PasswordStrengthLabel on PasswordStrength {
  String get label => switch (this) {
    PasswordStrength.veryWeak => 'Very weak',
    PasswordStrength.weak => 'Weak',
    PasswordStrength.fair => 'Fair',
    PasswordStrength.strong => 'Strong',
    PasswordStrength.veryStrong => 'Very strong',
  };
}

const _common = {
  'password',
  '123456',
  '12345678',
  '123456789',
  'qwerty',
  'abc123',
  '111111',
  '123123',
  'admin',
  'letmein',
  'welcome',
  'iloveyou',
  'monkey',
  'dragon',
  'football',
  'passw0rd',
  'qwerty123',
  '000000',
};

/// A rough estimate from length and character variety, with penalties for
/// common passwords and repeated or sequential runs.
PasswordStrength strengthOf(String password) {
  if (password.isEmpty) return PasswordStrength.veryWeak;
  final lower = password.toLowerCase();
  if (_common.contains(lower) || password.length < 6) {
    return PasswordStrength.veryWeak;
  }
  var pool = 0;
  if (RegExp('[a-z]').hasMatch(password)) pool += 26;
  if (RegExp('[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp('[0-9]').hasMatch(password)) pool += 10;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(password)) pool += 33;
  var bits = password.length * (log(max(pool, 10)) / ln2);
  // Long runs of one character or straight sequences add little.
  if (RegExp(r'(.)\1{2,}').hasMatch(password)) bits *= 0.75;
  if (RegExp(
    '0123|1234|2345|3456|4567|5678|6789|abcd|bcde|qwer|asdf',
  ).hasMatch(lower)) {
    bits *= 0.8;
  }
  return switch (bits) {
    < 36 => PasswordStrength.weak,
    < 60 => PasswordStrength.fair,
    < 90 => PasswordStrength.strong,
    _ => PasswordStrength.veryStrong,
  };
}
