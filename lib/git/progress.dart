/// One progress update emitted by git or git-lfs.
class GitProgress {
  const GitProgress({
    required this.phase,
    this.percent,
    this.completed,
    this.total,
    this.bytes,
    this.bytesPerSecond,
  });

  final String phase;
  final int? percent;
  final int? completed;
  final int? total;
  final int? bytes;
  final double? bytesPerSecond;

  double? get fraction => percent == null ? null : percent! / 100;

  static final _phases = [
    'Receiving objects',
    'Writing objects',
    'Resolving deltas',
    'Compressing objects',
    'Counting objects',
    'Enumerating objects',
    'Updating files',
    'Checking out files',
    'Unpacking objects',
    'Filtering content',
  ];

  static final _transfer = RegExp(
    r'(?:,\s*|\s+)([\d.]+\s*(?:B|KiB|MiB|GiB|KB|MB|GB))'
    r'(?:\s*/\s*[\d.]+\s*(?:B|KiB|MiB|GiB|KB|MB|GB))?'
    r'(?:\s*\|\s*([\d.]+\s*(?:B|KiB|MiB|GiB|KB|MB|GB))/s)?',
  );

  static GitProgress? parse(String line) {
    final text = line.trim();
    final lfs = RegExp(
      r'\b(Uploading|Downloading) LFS objects:\s*(\d+)%\s*'
      r'\((\d+)\s*/\s*(\d+)\)(.*)$',
    ).firstMatch(text);
    if (lfs != null) {
      final transfer = _transfer.firstMatch(lfs[5]!);
      return GitProgress(
        phase: '${lfs[1]} LFS objects',
        percent: int.parse(lfs[2]!),
        completed: int.parse(lfs[3]!),
        total: int.parse(lfs[4]!),
        bytes: _parseBytes(transfer?[1]),
        bytesPerSecond: _parseBytes(transfer?[2])?.toDouble(),
      );
    }

    for (final phase in _phases) {
      final match = RegExp(
        '(?:^|remote:\\s*)$phase:\\s*'
        r'(?:(\d+)%\s*\((\d+)\s*/\s*(\d+)\)|(\d+))(.*)$',
      ).firstMatch(text);
      if (match == null) continue;
      final transfer = _transfer.firstMatch(match[5]!);
      return GitProgress(
        phase: phase,
        percent: match[1] == null ? null : int.parse(match[1]!),
        completed: match[2] == null ? null : int.parse(match[2]!),
        total: match[3] == null ? null : int.parse(match[3]!),
        bytes: _parseBytes(transfer?[1]),
        bytesPerSecond: _parseBytes(transfer?[2])?.toDouble(),
      );
    }
    return null;
  }

  static int? _parseBytes(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'([\d.]+)\s*(B|KiB|MiB|GiB|KB|MB|GB)').firstMatch(value);
    if (match == null) return null;
    final amount = double.tryParse(match[1]!);
    if (amount == null) return null;
    final power = switch (match[2]!) {
      'B' => 0,
      'KiB' || 'KB' => 1,
      'MiB' || 'MB' => 2,
      _ => 3,
    };
    var multiplier = 1;
    for (var i = 0; i < power; i++) {
      multiplier *= 1024;
    }
    return (amount * multiplier).round();
  }
}

/// Splits arbitrary process-output chunks into progress updates. Git redraws
/// progress meters with carriage returns rather than newlines.
class GitProgressParser {
  String _pending = '';

  List<GitProgress> feed(String chunk) {
    _pending += chunk;
    final lines = _pending.split(RegExp(r'[\r\n]'));
    _pending = lines.removeLast();
    final result = <GitProgress>[];
    for (final line in [...lines, _pending]) {
      final progress = GitProgress.parse(line);
      if (progress != null) result.add(progress);
    }
    if (_pending.length > 4096) {
      _pending = _pending.substring(_pending.length - 4096);
    }
    return result;
  }
}
