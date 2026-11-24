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
  /// repository is bound to one account (see `RepoController.setAccount`).
  List<GitCredential>? credentialOverride;

  /// Credentials for the LFS server of this repository only. They are tried
  /// before the accounts for `git lfs` commands, so a repository can keep its
  /// LFS token separate from the Git account (see `RepoController.lfsCredential`).
  List<GitCredential> lfsCredentials = const [];

  /// Path or name of the git executable.
  static String executable = 'git';

  static bool get isSupported => !Platform.isIOS;

  /// Signed-in hosting accounts, used for network commands.
  static List<GitCredential> credentials = const [];

  static const _networkCommands = {
    'fetch',
    'pull',
    'push',
    'clone',
    'ls-remote',
    'lfs'
  };

  /// Proxy settings for every git process (see `NetworkSettings`), passed as
  /// environment variables so secrets never appear on the command line.
  static Map<String, String> networkEnv = const {};

  /// Disables system and global credential helpers, then adds one helper per
  /// signed-in server. The secrets travel in environment variables, so they
  /// never appear on the command line.
  ///
  /// [lfsCredentials] answer first for `git lfs` commands, where the LFS server
  /// may need a token of its own; for the other network commands the accounts
  /// come first. One server is answered once, so a credential never shadows
  /// itself.
  static (List<String>, Map<String, String>) credentialArgs(
    List<String> args,
    List<GitCredential> credentials, {
    List<GitCredential> lfsCredentials = const [],
  }) {
    if (args.isEmpty || !_networkCommands.contains(args.first)) {
      return (const [], const {});
    }
    final ordered = args.first == 'lfs'
        ? [...lfsCredentials, ...credentials]
        : [...credentials, ...lfsCredentials];
    final config = ['-c', 'credential.helper='];
    final env = <String, String>{};
    final servers = <String>{};
    var index = 0;
    for (final c in ordered) {
      if (!servers.add(c.server)) continue;
      env['EASYGIT_USER_$index'] = c.username;
      env['EASYGIT_PASS_$index'] = c.password;
      config
        // An empty helper resets the list, so only ours answers for this server.
        ..addAll(['-c', 'credential.${c.server}.helper='])
        ..addAll([
          '-c',
          'credential.${c.server}.helper=!f() { test "\$1" = get || return 0; '
              'echo "username=\$EASYGIT_USER_$index"; echo "password=\$EASYGIT_PASS_$index"; }; f',
        ]);
      index++;
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
  /// environment variables for this call only. [onStdout] and [onStderr] receive
  /// output chunks while the process is running; full output is still returned in logs.
  Future<String> run(List<String> args,
      {String? stdin,
      bool log = false,
      Duration? timeout,
      Map<String, String>? env,
      void Function(String chunk)? onStdout,
      void Function(String chunk)? onStderr}) async {
    final command = 'git ${args.map(_quote).join(' ')}';
    if (!isSupported) {
      throw GitException(command,
          'The git command line is not available on this platform.', -1);
    }
    final (credentialConfig, credentialEnv) = credentialArgs(
        args, credentialOverride ?? credentials,
        lfsCredentials: lfsCredentials);
    final Process process;
    try {
      process = await Process.start(
        executable,
        [
          '-c',
          'core.quotepath=false',
          '-c',
          'color.ui=never',
          ...credentialConfig,
          ...args
        ],
        workingDirectory: workDir,
        environment: {..._env, ...networkEnv, ...credentialEnv, ...?env},
      );
    } on ProcessException catch (e) {
      throw GitException(
          command,
          'Unable to start git (${e.message}). Is Git installed and on PATH?',
          -1);
    }
    const decoder = Utf8Decoder(allowMalformed: true);
    final out = () async {
      final output = StringBuffer();
      await for (final chunk in process.stdout.transform(decoder)) {
        output.write(chunk);
        onStdout?.call(chunk);
      }
      return output.toString();
    }();
    final err = () async {
      final output = StringBuffer();
      await for (final chunk in process.stderr.transform(decoder)) {
        output.write(chunk);
        onStderr?.call(chunk);
      }
      return output.toString();
    }();
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
        throw GitException(
            command, 'Timed out after ${timeout.inSeconds} s.', -2);
      }
    }
    final stdout = await out;
    final stderr = await err;

    if (log) {
      onLog?.call(GitCommandLog(
        time: DateTime.now(),
        command: command,
        exitCode: exitCode,
        output: [stdout.trim(), stderr.trim()]
            .where((s) => s.isNotEmpty)
            .join('\n'),
      ));
    }
    if (exitCode != 0) {
      final message = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
      throw GitException(
          command, message.isEmpty ? '$command failed' : message, exitCode);
    }
    return stdout;
  }

  static String _quote(String arg) =>
      arg.isEmpty || arg.contains(' ') ? '"$arg"' : arg;
}
