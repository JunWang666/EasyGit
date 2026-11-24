import 'package:easygit/state/lfs_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the server of an LFS endpoint is its origin', () {
    expect(LfsCredential.serverOf('https://lfs.example.com/team/app'),
        'https://lfs.example.com');
    expect(LfsCredential.serverOf('http://127.0.0.1:9000/x'), 'http://127.0.0.1:9000');
    expect(LfsCredential.serverOf('https://host.example.com:8443'), 'https://host.example.com:8443');
    expect(LfsCredential.serverOf('ssh://host/x'), isNull);
    expect(LfsCredential.serverOf(''), isNull);
    expect(LfsCredential.serverOf(null), isNull);
  });

  test('credentials belong to the server they were saved for', () {
    const credential =
        LfsCredential(server: 'https://lfs.example.com', username: 'u', token: 't');
    expect(credential.matches('https://lfs.example.com/team/app'), isTrue);
    expect(credential.matches('https://other.example.com/team/app'), isFalse);
    expect(credential.matches(null), isFalse);
    expect(credential.git.username, 'u');
    expect(credential.git.password, 't');
  });

  test('records survive a JSON round trip', () {
    const credential =
        LfsCredential(server: 'https://lfs.example.com', username: 'u', token: 'token');
    final copy = LfsCredential.fromJson(credential.toJson())!;
    expect(copy.server, credential.server);
    expect(copy.username, credential.username);
    expect(copy.token, credential.token);
    expect(LfsCredential.fromJson({'server': 'ssh://x', 'username': 'u', 'token': 't'}),
        isNull);
    expect(LfsCredential.fromJson({'server': 'https://x', 'username': '', 'token': 't'}),
        isNull);
  });

  test('the store key follows the folder, not the spelling', () {
    final key = LfsCredentialStore.keyFor(r'C:\DevCodes\EasyGit');
    expect(key, LfsCredentialStore.keyFor('C:/DevCodes/EasyGit/'));
    expect(key, startsWith('easygit.lfs.'));
    expect(key, isNot(LfsCredentialStore.keyFor(r'C:\DevCodes\Other')));
  });
}
