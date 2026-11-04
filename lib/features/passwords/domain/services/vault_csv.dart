import '../../../../core/i18n/i18n.dart';
import '../entities/vault_entry.dart';

/// A login read from a CSV export (before it gets an id).
typedef CsvLogin = ({
  String title,
  String url,
  String username,
  String password,
  String notes,
});

/// CSV import/export for passwords.
///
/// Import understands the exports of Chrome / Google Password Manager
/// (`name,url,username,password,note`), Bitwarden (`login_uri,
/// login_username,login_password…`), Firefox, Samsung Pass-style and
/// KeePass (`Title,Username,Password,URL,Notes`) by their header names.
/// Export uses Chrome's format, which most managers can import.
abstract final class VaultCsv {
  static const _title = ['name', 'title', 'account', 'site', 'item'];
  static const _url = [
    'url',
    'login_uri',
    'uri',
    'website',
    'web site',
    'origin',
    'origin_url',
    'login url',
  ];
  static const _username = [
    'username',
    'login_username',
    'user',
    'user name',
    'login',
    'email',
    'login name',
    'username_value',
  ];
  static const _password = [
    'password',
    'login_password',
    'pass',
    'password_value',
  ];
  static const _notes = ['note', 'notes', 'extra', 'comments', 'comment'];

  /// Logins in [csv]. Rows without a password are skipped. Throws
  /// [FormatException] if no password column can be found.
  static List<CsvLogin> parse(String csv) {
    final rows = parseRows(csv);
    if (rows.isEmpty) return const [];
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    int col(List<String> names) => header.indexWhere((h) => names.contains(h));
    final title = col(_title);
    final url = col(_url);
    final username = col(_username);
    final password = col(_password);
    final notes = col(_notes);
    if (password < 0) {
      throw FormatException(
        tr(
          'No "password" column found. Export the CSV from your browser or password manager.',
        ),
      );
    }
    String at(List<String> row, int i) =>
        i >= 0 && i < row.length ? row[i].trim() : '';

    return [
      for (final row in rows.skip(1))
        if (at(row, password).isNotEmpty)
          (
            title: at(row, title).isNotEmpty
                ? at(row, title)
                : _hostOf(at(row, url)) ?? at(row, username),
            url: at(row, url),
            username: at(row, username),
            password: row[password],
            notes: at(row, notes),
          ),
    ];
  }

  /// Chrome-style CSV of [entries].
  static String export(List<VaultEntry> entries) {
    final buf = StringBuffer('name,url,username,password,note\r\n');
    for (final e in entries) {
      buf.write(
        [e.title, e.url, e.username, e.password, e.notes].map(_field).join(','),
      );
      buf.write('\r\n');
    }
    return buf.toString();
  }

  static String _field(String v) =>
      RegExp(r'[",\r\n]').hasMatch(v) || v.startsWith(' ') || v.endsWith(' ')
      ? '"${v.replaceAll('"', '""')}"'
      : v;

  static String? _hostOf(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    final host = uri?.host ?? '';
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// RFC 4180 rows: quoted fields, doubled quotes and line breaks inside
  /// quotes. Also accepts a UTF-8 BOM and LF line endings.
  static List<List<String>> parseRows(String csv) {
    var text = csv;
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        endField();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}
