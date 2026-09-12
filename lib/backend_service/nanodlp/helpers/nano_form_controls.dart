/*
* Orion - NanoDLP Form Controls
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

/// Browser-equivalent serializer for NanoDLP's generated profile pages.
///
/// NanoDLP has no JSON "create profile" call. `GET /profile/clone/<id>`
/// renders the same form as `/profile/edit/<id>` and the server copies
/// nothing from the source profile: the POSTed form *is* the new profile, so
/// every control has to be echoed back or the missing ones are written as
/// zero/empty. This class extracts those controls the way a browser would
/// submit them, without needing an HTML parsing dependency.
///
/// Handled like a browser:
/// * `input` — skipped when unnamed, `disabled`, or an unchecked
///   checkbox/radio; `submit`/`button`/`reset`/`file`/`image` are never sent.
/// * `select` — the selected option's `value` (falling back to its label, then
///   the first option).
/// * `textarea` — its text content.
/// * HTML entities in values are decoded.
/// * Duplicate names keep the first occurrence (Go's `FormValue` semantics).
class NanoFormControls {
  const NanoFormControls._();

  /// Serialize the controls of the form with [formId] — or the first form on
  /// the page when no id matches — into the body a browser would POST.
  static Map<String, String> parse(String html, {String? formId = 'setup'}) {
    final body = _formBody(html, formId);
    if (body == null) return const {};
    return _serialize(body);
  }

  /// Returns the inner HTML of the requested form, or null when the page has
  /// no forms at all. A form whose id doesn't match [formId] is kept as a
  /// fallback so vendor template tweaks don't break cloning.
  static String? _formBody(String html, String? formId) {
    final formRe = RegExp(r'<form\b', caseSensitive: false);
    String? fallback;
    for (final match in formRe.allMatches(html)) {
      final tagEnd = _tagEnd(html, match.start);
      if (tagEnd == null) continue;
      final attrs = _attributes(html.substring(match.start, tagEnd));
      final close = html.indexOf('</form', tagEnd);
      final body = html.substring(tagEnd, close < 0 ? html.length : close);
      if (formId == null || attrs['id'] == formId) return body;
      fallback ??= body;
    }
    return fallback;
  }

  static Map<String, String> _serialize(String body) {
    final out = <String, String>{};
    var index = 0;
    var selectName = '';
    var inSelect = false;
    var options = <_Option>[];

    while (index < body.length) {
      final lt = body.indexOf('<', index);
      if (lt < 0) break;
      if (body.startsWith('<!--', lt)) {
        final commentEnd = body.indexOf('-->', lt);
        index = commentEnd < 0 ? body.length : commentEnd + 3;
        continue;
      }
      final tagEnd = _tagEnd(body, lt);
      if (tagEnd == null) break;
      final tag = body.substring(lt, tagEnd);

      switch (_tagName(tag)) {
        case 'input':
          final attrs = _attributes(tag);
          final name = attrs['name'];
          if (name != null && name.isNotEmpty && _isSubmittedInput(attrs)) {
            out.putIfAbsent(name, () => attrs['value'] ?? '');
          }
        case 'select':
          final attrs = _attributes(tag);
          selectName = attrs['name'] ?? '';
          inSelect = selectName.isNotEmpty && !attrs.containsKey('disabled');
          options = <_Option>[];
        case 'option':
          if (inSelect) {
            final attrs = _attributes(tag);
            final textEnd = body.indexOf('<', tagEnd);
            final label = _unescape((textEnd < 0
                    ? body.substring(tagEnd)
                    : body.substring(tagEnd, textEnd))
                .trim());
            options.add(_Option(
              attrs['value'] ?? label,
              attrs.containsKey('selected'),
            ));
          }
        case '/select':
          if (inSelect) {
            out.putIfAbsent(selectName, () => _selectedValue(options));
            inSelect = false;
          }
        case 'textarea':
          final attrs = _attributes(tag);
          final name = attrs['name'];
          final close = body.indexOf('</textarea', tagEnd);
          final raw = close < 0
              ? body.substring(tagEnd)
              : body.substring(tagEnd, close);
          if (name != null &&
              name.isNotEmpty &&
              !attrs.containsKey('disabled')) {
            out.putIfAbsent(name, () => _normalizeNewlines(_unescape(raw)));
          }
          if (close < 0) {
            index = body.length;
          } else {
            index = _tagEnd(body, close) ?? body.length;
          }
          continue;
      }
      index = tagEnd;
    }
    return out;
  }

  /// Mirrors browser form submission rules for `<input>` elements.
  static bool _isSubmittedInput(Map<String, String> attrs) {
    if (attrs.containsKey('disabled')) return false;
    switch ((attrs['type'] ?? 'text').toLowerCase()) {
      case 'submit':
      case 'button':
      case 'reset':
      case 'file':
      case 'image':
        return false;
      case 'checkbox':
      case 'radio':
        return attrs.containsKey('checked');
      default:
        return true;
    }
  }

  static String _selectedValue(List<_Option> options) {
    if (options.isEmpty) return '';
    for (final option in options) {
      if (option.selected) return option.value;
    }
    return options.first.value;
  }

  /// Returns the index just past the `>` closing the tag that starts at
  /// [start], ignoring `>` inside quoted attribute values.
  static int? _tagEnd(String html, int start) {
    String? quote;
    for (var i = start + 1; i < html.length; i++) {
      final ch = html[i];
      if (quote != null) {
        if (ch == quote) quote = null;
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '>') {
        return i + 1;
      }
    }
    return null;
  }

  /// Tag name, lower-cased. Closing tags are prefixed with `/`.
  static String _tagName(String tag) {
    var i = 1;
    var closing = false;
    if (i < tag.length && tag[i] == '/') {
      closing = true;
      i++;
    }
    final start = i;
    while (
        i < tag.length && !_isSpace(tag[i]) && tag[i] != '>' && tag[i] != '/') {
      i++;
    }
    final name = tag.substring(start, i).toLowerCase();
    return closing ? '/$name' : name;
  }

  /// Parses a tag's attributes. Attribute names are lower-cased; valueless
  /// attributes (e.g. `checked`, `disabled`) map to an empty string.
  static Map<String, String> _attributes(String tag) {
    final attrs = <String, String>{};
    var i = 0;
    while (i < tag.length && !_isSpace(tag[i])) {
      i++;
    }
    while (i < tag.length) {
      while (i < tag.length && (_isSpace(tag[i]) || tag[i] == '/')) {
        i++;
      }
      final nameStart = i;
      while (i < tag.length &&
          !_isSpace(tag[i]) &&
          tag[i] != '=' &&
          tag[i] != '/' &&
          tag[i] != '>') {
        i++;
      }
      if (i == nameStart) break;
      final name = tag.substring(nameStart, i).toLowerCase();
      while (i < tag.length && _isSpace(tag[i])) {
        i++;
      }
      var value = '';
      if (i < tag.length && tag[i] == '=') {
        i++;
        while (i < tag.length && _isSpace(tag[i])) {
          i++;
        }
        if (i < tag.length && (tag[i] == '"' || tag[i] == "'")) {
          final quote = tag[i++];
          final valueStart = i;
          while (i < tag.length && tag[i] != quote) {
            i++;
          }
          value = tag.substring(valueStart, i);
          if (i < tag.length) i++;
        } else {
          final valueStart = i;
          while (i < tag.length && !_isSpace(tag[i]) && tag[i] != '>') {
            i++;
          }
          value = tag.substring(valueStart, i);
        }
      }
      attrs[name] = _unescape(value);
    }
    return attrs;
  }

  static bool _isSpace(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\f';

  /// HTML parsers normalise CRLF (and lone CR) to LF, so a browser submits
  /// textarea values with LF newlines however the server emitted them. The
  /// printer stores what it receives, and the vendor web UI therefore stores
  /// LF for cloned code blocks too.
  static String _normalizeNewlines(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  static final _entityRe = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

  /// Decodes the entities NanoDLP emits in textarea content and attributes.
  static String _unescape(String value) {
    if (!value.contains('&')) return value;
    return value.replaceAllMapped(_entityRe, (match) {
      final entity = match.group(1)!;
      if (entity.startsWith('#')) {
        final hex = entity[1] == 'x' || entity[1] == 'X';
        final code = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      switch (entity.toLowerCase()) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return '\u00a0';
      }
      return match.group(0)!;
    });
  }
}

class _Option {
  const _Option(this.value, this.selected);

  final String value;
  final bool selected;
}
