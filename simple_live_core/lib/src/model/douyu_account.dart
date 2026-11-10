/// Login material supplied by the user, never proof of a valid server session.
class DouyuAccountCookies {
  final Map<String, String> values;

  DouyuAccountCookies._(Map<String, String> values)
    : values = Map.unmodifiable(values);

  factory DouyuAccountCookies.parse(String input) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(input)) {
      throw const FormatException('Cookie 不能包含换行或控制字符');
    }
    final values = <String, String>{};
    for (final part in input.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) continue;
      if (value.isNotEmpty) values[name] = value;
    }
    return DouyuAccountCookies._(values);
  }

  String? get deviceId => values['dy_did'] ?? values['acf_did'];

  bool get hasSession =>
      values.containsKey('dy_auth') || values.containsKey('acf_jwt_token');

  bool get canUseForPlayback => hasSession && deviceId != null;

  /// Only send session/device cookies to the playback API, not passport tokens
  /// (such as LTP0) or unrelated browser tracking cookies.
  String get playbackCookie => values.entries
      .where(
        (entry) => const {
          'dy_auth',
          'acf_jwt_token',
          'dy_did',
          'acf_did',
          'acf_uid',
          'acf_username',
          'acf_nickname',
          'acf_auth',
          'acf_stk',
        }.contains(entry.key),
      )
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');
}
