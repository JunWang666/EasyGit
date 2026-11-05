import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// HTTPS credentials for one server, supplied to git by EasyGit itself.
class GitCredential {
  const GitCredential(this.server, this.username, this.password);

  /// URL prefix such as `https://github.com`.
  final String server;
  final String username;
  final String password;
}

/// Runs the `git` command line in a working directory.
///
/// Desktop platforms (Windows, Linux, macOS) use the git executable on PATH.
/// iPadOS does not allow spawning processes, so [isSupported] is false there
/// and a different backend (for example libgit2 over FFI) would be required.
class GitRunner {
  GitRunner(this.workDir, {this.onLog});

  final String workDir;
  void Function(GitCommandLog log)? onLog;

  /// Credentials for this runner only, in place of [credentials]. Set when a
  /// repository is bound to one account (see `RepoController.pushAccountId`).
  List<GitCredential>? credentialOverride;

  /// Path or name of the git executable.
  static String executable = 'git';

  static bool get isSupported => !Platform.isIOS;

  /// Signed-in hosting accounts, used for network commands.
  static List<GitCredential> credentials = const [];

  static const _networkCommands = {'fetch', 'pull', 'push', 'clone', 'ls-remote', 'lfs'};

  /// Proxy settings for every git process (see `NetworkSettings`), passed as
  /// environment variables so secrets never appear on the command line.
  static Map<String, String> networkEnv = const {};

  /// Adds a credential helper per signed-in server. The secrets travel in
  /// environment variables, so they never appear on the command line.
  static (List<String>, Map<String, String>) _credentialArgs(
      List<String> args, List<GitCredential> credentials) {
    if (credentials.isEmpty || args.isEmpty || !_networkCommands.contains(args.first)) {
      return (const [], const {});
    }
    final config = <String>[];
    final env = <String, String>{};
    for (var i = 0; i < credentials.length; i++) {
      final c = credentials[i];
      env['EASYGIT_USER_$i'] = c.username;
      env['EASYGIT_PASS_$i'] = c.password;
      config
        // An empty helper resets the list, so only ours answers for this server.
        ..addAll(['-c', 'credential.${c.server}.helper='])
        ..addAll([
          '-c',
          'credential.${c.server}.helper=!f() { test "\$1" = get || return 0; '
              'echo "username=\$EASYGIT_USER_$i"; echo "password=\$EASYGIT_PASS_$i"; }; f',
        ]);
    }
    return (config, env);
  }

  static const _env = {
    // Never block waiting for a terminal prompt; credential helpers still work.
    'GIT_TERMINAL_PROMPT': '0',
    // Background status refreshes must not take the index lock.
    'GIT_OPTIONAL_LOCKS': '0',
    // Operations such as `rebase --continue` must not open an editor.
    'GIT_EDITOR': 'true',
  };

  /// Runs `git <args>` and returns stdout. Throws [GitException] on failure.
  ///
  /// When [log] is true the command and its output go to the Git console.
  /// With [timeout] the process is killed when it takes longer. [env] adds
  /// environment variables for this call only.
  Future<String> run(List<String> args,
      {String? stdin, bool log = false, Duration? timeout, Map<String, String>? env}) async {
    final command = 'git ${args.map(_quote).join(' ')}';
    if (!isSupported) {
      throw GitException(command,
          'The git command line is not available on this platform.', -1);
    }
    final (credentialConfig, credentialEnv) =
        _credentialArgs(args, credentialOverride ?? credentials);
    final Process process;
    try {
      process = await Process.start(
        executable,
        ['-c', 'core.quotepath=false', '-c', 'color.ui=never', ...credentialConfig, ...args],
        workingDirectory: workDir,
        environment: {..._env, ...networkEnv, ...credentialEnv, ...?env},
      );
    } on ProcessException catch (e) {
      throw GitException(command,
          'Unable to start git (${e.message}). Is Git installed and on PATH?', -1);
    }
    const decoder = Utf8Decoder(allowMalformed: true);
    final out = process.stdout.transform(decoder).join();
    final err = process.stderr.transform(decoder).join();
    try {
      if (stdin != null) process.stdin.add(utf8.encode(stdin));
      await process.stdin.close();
    } catch (_) {
      // The process may exit before reading stdin.
    }
    final int exitCode;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill();
        throw GitException(command, 'Timed out after ${timeout.inSeconds} s.', -2);
      }
    }
    final stdout = await out;
    final stderr = await err;

    if (log) {
      onLog?.call(GitCommandLog(
        time: DateTime.now(),
        command: command,
        exitCode: exitCode,
        output: [stdout.trim(), stderr.trim()].where((s) => s.isNotEmpty).join('\n'),
      ));
    }
    if (exitCode != 0) {
      final message = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
      throw GitException(command, message.isEmpty ? '$command failed' : message, exitCode);
    }
    return stdout;
  }

  static String _quote(String arg) =>
      arg.isEmpty || arg.contains(' ') ? '"$arg"' : arg;
}
