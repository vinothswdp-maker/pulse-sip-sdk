import 'dart:convert';
import 'dart:io';

import 'pulse_sip_config.dart';

/// Logs in against Pulse's own account backend (ConnectHub) and resolves the
/// SIP proxy config to register with, so the host app never needs to know a
/// SIP domain/extension — only the account code, username, and password the
/// person already has for their Pulse account.
///
/// Request/response shape is fixed to `POST /auth/login/app`'s existing
/// contract (see project notes) — this is not a generic multi-backend
/// adapter, it's this one API. [username]/[password] here are the account
/// login credentials; the actual SIP extension/domain to register with come
/// back in the response (`m_memberExtensionNo`, `p_proxyDomainName`) — the
/// login password itself is reused as the SIP password (never sent back over
/// the wire), the same way the extension's account password is also its SIP
/// auth password on this platform.
class PulseRemoteConfig {
  PulseRemoteConfig._();

  static const _loginUrl = 'https://connecthub.pulsework360.com/auth/login/app';
  static const _timeout = Duration(seconds: 10);

  static Future<PulseSipConfig> authenticate({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_loginUrl)).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'accountcode': companyCode,
        'membername': username,
        'memberpassword': password,
      })));

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw StateError('Login failed: HTTP ${response.statusCode}');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw StateError('Login failed: ${json['message'] ?? 'no account data returned'}');
      }

      final proxyDomain = data['p_proxyDomainName'] as String;
      final extension = data['m_memberExtensionNo'].toString();

      return PulseSipConfig(
        webSocketUrl: 'wss://$proxyDomain:8089/ws',
        sipUser: extension,
        sipPassword: password,
        sipDomain: proxyDomain,
        displayName: data['m_memberName'] as String?,
      );
    } finally {
      client.close();
    }
  }
}
