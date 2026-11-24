import 'dart:convert';
import 'dart:io';

import '../net/network.dart';
import 'git_runner.dart';

/// The small text file git stores in place of an LFS-managed file.
class LfsPointer {
  const LfsPointer(this.oid, this.size);

  final String oid;
  final int size;

  static const _version = 'version https://git-lfs.github.com/spec/v1';

  /// Parses pointer text, or returns null if [text] is not a pointer.
  static LfsPointer? parse(String? text) {
    if (text == null || text.length > 1024 || !text.startsWith(_version))
      return null;
    final oid = RegExp(r'^oid sha256:([0-9a-f]{64})\s*$', multiLine: true)
        .firstMatch(text)?[1];
    final size = int.tryParse(
        RegExp(r'^size (\d+)\s*$', multiLine: true).firstMatch(text)?[1] ?? '');
    if (oid == null || size == null) return null;
    return LfsPointer(oid, size);
  }
}

/// One entry of `git lfs ls-files --json`.
class LfsFile {
  const LfsFile({
    required this.path,
    required this.size,
    required this.oid,
    required this.downloaded,
    required this.checkedOut,
  });

  final String path;
  final int size;
  final String oid;

  /// The object is in the local LFS store.
  final bool downloaded;

  /// The working tree has the real content rather than the pointer.
  final bool checkedOut;
}

List<LfsFile> parseLfsFilesJson(String json) {
  final data = jsonDecode(json);
  final files = data is Map ? data['files'] : null;
  if (files is! List) return const [];
  return [
    for (final f in files.cast<Map<String, dynamic>>())
      LfsFile(
        path: f['name'] as String? ?? '',
        size: (f['size'] as num?)?.toInt() ?? 0,
        oid: f['oid'] as String? ?? '',
        downloaded: f['downloaded'] == true,
        checkedOut: f['checkout'] == true,
      ),
  ];
}

/// A folder or file in the LFS file browser.
class LfsTreeNode {
  const LfsTreeNode({
    required this.path,
    required this.name,
    this.file,
    this.children = const [],
  });

  final String path;
  final String name;
  final LfsFile? file;
  final List<LfsTreeNode> children;

  bool get isFolder => file == null;

  List<LfsFile> get files => [
        if (file != null) file!,
        for (final child in children) ...child.files,
      ];

  int get fileCount => files.length;
  int get totalSize => files.fold(0, (sum, f) => sum + f.size);
}

/// Builds a sorted directory tree from repository-relative LFS paths.
LfsTreeNode buildLfsTree(Iterable<LfsFile> files) =>
    _buildLfsNode('', '', files.toList());

LfsTreeNode _buildLfsNode(String path, String name, List<LfsFile> files) {
  final direct = <LfsFile>[];
  final folders = <String, List<LfsFile>>{};
  for (final file in files) {
    final relative =
        path.isEmpty ? file.path : file.path.substring(path.length + 1);
    final slash = relative.indexOf('/');
    if (slash < 0) {
      direct.add(file);
    } else {
      folders.putIfAbsent(relative.substring(0, slash), () => []).add(file);
    }
  }
  direct.sort((a, b) => a.path.compareTo(b.path));
  final folderNames = folders.keys.toList()..sort();
  return LfsTreeNode(
    path: path,
    name: name,
    children: [
      for (final folder in folderNames)
        _buildLfsNode(
            path.isEmpty ? folder : '$path/$folder', folder, folders[folder]!),
      for (final file in direct)
        LfsTreeNode(
            path: file.path, name: file.path.split('/').last, file: file),
    ],
  );
}

class LfsCleanResult {
  const LfsCleanResult({required this.cleaned, required this.skipped});

  final int cleaned;
  final int skipped;
}

/// One progress-meter update emitted by git-lfs.
class LfsTransferProgress {
  const LfsTransferProgress({
    required this.uploading,
    required this.percent,
    required this.completedFiles,
    required this.totalFiles,
  });

  final bool uploading;
  final int percent;
  final int completedFiles;
  final int totalFiles;

  double get fraction => percent / 100;

  static LfsTransferProgress? parse(String text) {
    final match = RegExp(
      r'\b(Uploading|Downloading) LFS objects:\s*(\d+)%\s*\((\d+)\s*/\s*(\d+)\)',
    ).firstMatch(text);
    if (match == null) return null;
    return LfsTransferProgress(
      uploading: match[1] == 'Uploading',
      percent: int.parse(match[2]!),
      completedFiles: int.parse(match[3]!),
      totalFiles: int.parse(match[4]!),
    );
  }
}

/// Parses `git check-attr -z <attrs...>` output into `path -> attr -> value`.
Map<String, Map<String, String>> parseCheckAttrZ(String out) {
  final parts = out.split('\x00');
  final result = <String, Map<String, String>>{};
  for (var i = 0; i + 2 < parts.length; i += 3) {
    result.putIfAbsent(parts[i], () => {})[parts[i + 1]] = parts[i + 2];
  }
  return result;
}

/// Values of interest from `git lfs env`.
class LfsEnv {
  const LfsEnv({this.endpoint, this.auth, this.mediaDir});

  final String? endpoint;
  final String? auth;

  /// Local object store (`.git/lfs/objects`).
  final String? mediaDir;

  static LfsEnv parse(String out) {
    final ep = RegExp(r'^Endpoint=(\S+)(?: \(auth=([^)]*)\))?', multiLine: true)
        .firstMatch(out);
    final media = RegExp(r'^LocalMediaDir=(.+)$', multiLine: true)
        .firstMatch(out)?[1]
        ?.trim();
    return LfsEnv(endpoint: ep?[1], auth: ep?[2], mediaDir: media);
  }

  /// Where the object with [oid] lives locally, if the store is known.
  String? objectPath(String oid) => mediaDir == null || oid.length < 4
      ? null
      : '$mediaDir/${oid.substring(0, 2)}/${oid.substring(2, 4)}/$oid';
}

/// Where the LFS server URL comes from. Precedence (tested with git-lfs 3.7):
/// local `lfs.url` > committed `.lfsconfig` > derived from the remote URL.
/// `remote.<name>.lfsurl` loses to `.lfsconfig`, so EasyGit does not use it.
enum LfsUrlSource {
  automatic('Automatic (from the remote URL)'),
  shared('Shared with the team (.lfsconfig, committed)'),
  local('This computer only (git config lfs.url)');

  const LfsUrlSource(this.label);

  final String label;
}

class LfsServerConfig {
  const LfsServerConfig({this.localUrl, this.sharedUrl, this.effective});

  final String? localUrl;
  final String? sharedUrl;
  final String? effective;

  LfsUrlSource get source => localUrl != null
      ? LfsUrlSource.local
      : (sharedUrl != null ? LfsUrlSource.shared : LfsUrlSource.automatic);
}

enum LfsServerStatus {
  ok,
  needsLogin,
  notFound,
  unreachable,
  certificate,
  error
}

class LfsServerTest {
  const LfsServerTest(this.status, this.detail);

  final LfsServerStatus status;
  final String detail;

  String get summary => switch (status) {
        LfsServerStatus.ok => 'The LFS server answered.',
        LfsServerStatus.needsLogin =>
          'The server needs credentials. Set LFS credentials in this dialog, or add an '
              'account for this server under Accounts.',
        LfsServerStatus.notFound =>
          'No LFS service at this address (HTTP 404). Check the URL.',
        LfsServerStatus.unreachable =>
          'The server could not be reached. Check the address and proxy.',
        LfsServerStatus.certificate => 'The server certificate is not trusted.',
        LfsServerStatus.error => 'The server returned an error.',
      };
}

/// Sends an empty LFS batch request to [endpoint], using the network settings
/// and the best credentials available: [credential] (the repository's own LFS
/// credentials) when it belongs to the same host, else the signed-in account
/// for that host.
Future<LfsServerTest> testLfsServer(String endpoint,
    {GitCredential? credential}) async {
  final uri = Uri.tryParse('$endpoint/objects/batch');
  if (uri == null || !uri.scheme.startsWith('http')) {
    return const LfsServerTest(
        LfsServerStatus.error, 'Only HTTP(S) LFS servers can be tested here.');
  }
  final client = NetworkSettings.httpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.git-lfs+json')
      ..set(HttpHeaders.contentTypeHeader, 'application/vnd.git-lfs+json')
      ..set(HttpHeaders.userAgentHeader, 'EasyGit');
    final host = uri.host.toLowerCase();
    final own = credential != null &&
            Uri.tryParse(credential.server)?.host.toLowerCase() == host
        ? credential
        : null;
    final auth = own ??
        GitRunner.credentials
            .where((c) => Uri.tryParse(c.server)?.host.toLowerCase() == host)
            .firstOrNull;
    if (auth != null) {
      request.headers.set(HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('${auth.username}:${auth.password}'))}');
    }
    request.write(jsonEncode({
      'operation': 'download',
      'transfers': ['basic'],
      'objects': <Object>[],
    }));
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    final code = response.statusCode;
    final detail =
        'HTTP $code from $uri${auth == null ? ' (no saved credentials)' : ''}';
    if (code < 300 || code == 422)
      return LfsServerTest(LfsServerStatus.ok, detail);
    if (code == 401 || code == 403)
      return LfsServerTest(LfsServerStatus.needsLogin, detail);
    if (code == 404) return LfsServerTest(LfsServerStatus.notFound, detail);
    return LfsServerTest(LfsServerStatus.error, detail);
  } on HandshakeException catch (e) {
    return LfsServerTest(LfsServerStatus.certificate, e.message);
  } on SocketException catch (e) {
    return LfsServerTest(LfsServerStatus.unreachable, e.message);
  } catch (e) {
    return LfsServerTest(LfsServerStatus.unreachable, '$e');
  } finally {
    client.close(force: true);
  }
}

/// "3.0 MB" style sizes.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
