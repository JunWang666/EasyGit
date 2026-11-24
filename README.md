# EasyGit

A cross-platform Git client written in Flutter. Its visual style follows the JetBrains New UI
(Darcula and Light themes), but the layout is built for Git itself rather than around an
editor.

## Layout

- **Sidebar**
  - **Repositories**: every repository you added, with its branch, ahead/behind counts and
    number of local changes. Click to switch.
  - The selected repository's views: **Local Changes**, **History**, **Branches**, **Stashes**,
    **Worktrees**, **Git LFS**, **Repo Files** and **Settings**.
  - **Branches**: click shows the tip in History, double-click checks out, right-click opens
    branch actions.
  - **Remotes**, **Tags** and **Stashes** (click a stash to see its changes; apply, pop, drop).
  - **Worktrees**: `git worktree` checkouts of the same repository. Add one for a new or
    existing branch, open it in the sidebar as its own repository, remove it, or prune stale
    ones.
- **Local Changes**: the changed files (*Changes* and *Unversioned Files*, with checkboxes
  instead of a staging area) and the commit box on the left, and the selected file's diff on
  the right. Arrow keys move through the files.
- **History**: the commit graph with Branch/User/text filters on top. Below it are the
  selected commit's message and changed files, and the selected file's diff.
- **Repo Files**: the repository's own configuration and documentation files in a list, with
  an editor on the right that shows them as entries instead of raw text (see Features).
- **Toolbar**: repository and branch widgets (the branch widget opens the Branches popup),
  then Fetch, Pull, Push, Commit, Stash and Branch.
- **Status bar**: path, **Tasks**, branch, and a **Console** toggle that shows every git
  command run on your behalf.

## Features

- Side-by-side or unified line diffs (Myers algorithm) with next/previous difference.
- **Branch actions**: checkout (remote branches get a tracking branch), new branch, checkout
  and rebase, rebase onto, merge into current, push, rename, delete, new worktree. Merge or
  rebase in progress shows a badge with Continue and Abort.
- **Commit actions**: copy hash, cherry-pick, checkout revision, reset (soft/mixed/hard/keep),
  revert, new branch, new tag.
- Open, clone, or `git init` a folder that is not a repository yet.
- **Tasks** tracks clone, fetch, pull, push, LFS transfers and other operations across all
  repositories. The bottom bar shows live progress and speed; opening it reveals each stage,
  transferred bytes, completed operations and failures. Clone runs in the background instead
  of blocking the window.
- **Repository Settings** saves the default commit identity and fetch/push account for each
  repository. Commit and push dialogs use these defaults and allow a one-operation override.
- **GitHub, GitLab and Gitea/Forgejo accounts** (including GitHub Enterprise, self-managed
  GitLab and Codeberg), signed in with a personal access token:
  - The clone dialog has a tab per account, listing its repositories with search.
  - Fetch, pull, push and clone over HTTPS use only EasyGit's accounts, never the system or
    global Git credential helpers. Cloning from an account also selects it for the new repository.
  - Tokens are stored in the system credential store (Windows Credential Manager, macOS
    Keychain, libsecret on Linux), never in plain files.
  - You get "Open on GitHub/GitLab" for the repository, commits, files and branches, and
    "Create Pull Request / Merge Request" for local branches (it pushes first if needed).
  - Manage Remotes lets you add, edit and remove remotes.
  - **Other server (self-hosted Git / LFS)** accounts store a username and password or
    token for any HTTPS server (self-hosted Gitea, GitLab, Gogs, Bitbucket Data Center, or a
    standalone LFS server). They are used for that host only.
- **Git LFS** stays out of the way until it matters:
  - LFS files carry an `LFS` tag in file lists. Their diffs show old and new size, object ids
    and image previews instead of pointer text. A version that is not downloaded has a
    Download button.
  - When a commit includes files of 50 MB or more that are not in LFS, EasyGit offers to
    track them (`*.ext`) and commits `.gitattributes` with them.
  - The first-class **Git LFS** tab shows files in an expandable folder tree. Download a file
    or a whole folder on demand, upload selected objects without pushing a Git ref, or clear
    local content and cached objects while keeping Git pointers. Modified files and objects
    needed only by unpushed commits are protected. LFS uploads, including those started by
    Git push, show a live percentage and file-count progress bar. LFS Settings contains setup
    (one-click `git lfs install --local`), tracked patterns, and the LFS server.
  - The LFS server can be automatic (from the remote), shared with the team (`.lfsconfig`) or
    set for this computer only (`lfs.url`), and has a connection test. Precedence follows
    git-lfs: local `lfs.url` > `.lfsconfig` > derived from the remote.
  - The LFS server can need credentials of its own: **LFS Settings > Credentials** saves a
    username and password or token for the LFS server of that repository only. They stay in
    the system credential store (never in the repository), are used by `git lfs` before the
    account tokens, and the connection test uses them too. That covers a standalone LFS server
    that is not the Git remote, or a token that must not be used for Git.
- **Repo Files** keeps the files that tell Git and the hosting site how to treat the
  repository in one place: `.gitignore`, `.gitattributes`, `.lfsconfig`, `README.md` and
  `.editorconfig`, plus any other file you add with **New File...**.
  - The files are edited as entries, not as raw text: `.gitignore` is a list of patterns
    (with *folder* and *kept* tags and a comment line kept in place), `.gitattributes` is a
    list of pattern → attributes rows, and `.lfsconfig` and `.editorconfig` are sections of
    `key = value` entries. Add, edit and remove an entry in place; lines you did not touch,
    comments and spacing included, are written back unchanged. `README.md` and files with an
    unknown format keep a text editor.
  - Built-in templates: `.gitignore` for Dart/Flutter, Node.js, Python, Java, C#/.NET, Go,
    Rust, Xcode, JetBrains IDEs, VS Code, OS junk and secrets; `.gitattributes` for line
    endings, Git LFS patterns, language statistics and binary formats; `.lfsconfig` for a
    shared LFS server, `fetchexclude` and lock verification; four `README.md` layouts; and a
    common `.editorconfig`. Templates that fit the files in the repository root are marked
    *Recommended*.
  - **Templates...** on an existing file either replaces its content or appends the template
    after it, separated by a blank line. A file that does not exist yet opens on the template
    gallery instead of an empty editor.
  - Saving writes the file to the working tree, so it shows up in Local Changes and is
    committed from there. Ctrl+S saves, a dirty file has a dot in the list, and the tab badge
    counts the managed files that have local changes.
- **Network & Proxy** (gear menu): use Git's own configuration, the system proxy (Windows,
  macOS, environment), a manual HTTP or SOCKS proxy with optional credentials, or no proxy.
  It includes a NO_PROXY list, an option to connect directly to self-hosted servers, and a
  connection test. EasyGit passes these settings to its own git and git-lfs processes
  through environment variables and never edits your global gitconfig. Network errors come
  with a plain explanation and a button that opens the right setting.

### Shortcuts

| Action | Windows / Linux | macOS / iPadOS |
| --- | --- | --- |
| Repository views | Ctrl+1 … Ctrl+8 | ⌘1 … ⌘8 |
| Commit (focus message) | Ctrl+K | ⌘K |
| Commit now | Ctrl+Enter | ⌘Enter |
| Pull | Ctrl+T | ⌘T |
| Push | Ctrl+Shift+K | ⇧⌘K |
| Save repo file (Repo Files) | Ctrl+S | ⌘S |
| Toggle console | Ctrl+` | ⌘` |
| Refresh | F5 | F5 |

## Requirements

- Flutter 3.24 or newer.
- Git 2.25 or newer on `PATH`. The app runs the `git` command line.

## Setup

```bash
flutter pub get
```

```bash
flutter run -d windows
```

Use `-d linux` or `-d macos` for the other desktops.

### macOS

The app starts `git` and reads folders you choose, so the App Sandbox is turned off in
`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.

### Windows

Building needs Visual Studio with the "Desktop development with C++" workload, including the
C++ CMake tools. Developer Mode must also be on (Settings > System > For developers), because
Flutter plugins rely on symlinks.

#### Installer

The installer is compiled with [Inno Setup](https://jrsoftware.org/isinfo.php) from a release
build:

```bash
flutter build windows --release
ISCC.exe windows\installer\easygit.iss
```

The result is `dist\EasyGit-<version>-setup.exe`. For a new release, bump `version` in
`pubspec.yaml` and `AppVersion` in `windows\installer\easygit.iss` together. The Windows 11
Explorer context menu is a signed sparse package; `windows\shell_extension\package.ps1` packs
and signs it into the release folder, and when the `.msix` is missing the installer skips that
step (the menu can still be added later from the app).

### Linux

Folder pickers use `zenity` (or `kdialog`), so install one of them.

### iPadOS

The UI is touch-friendly: long-press opens context menus and the splitters can be dragged.
iPadOS does not let apps start processes, though, so the `git` command-line backend cannot
run there, and the welcome screen says so. Real iPad support needs a native backend, such as
libgit2 called through `dart:ffi`, behind the same `GitRepository` API.

## Project layout

```
lib/
  git/            git CLI runner, repository operations, graph layout, line diff,
                  repo file templates (.gitignore, .gitattributes, README, ...)
  hosting/        GitHub / GitLab / Gitea API, remote URL parsing, web links
  state/          ReposState (sidebar repositories), RepoController (one repository),
                  AccountsStore, AppSettings
  theme/          IdeColors (New UI Dark and Light palettes)
  ui/
    shell/        main window, sidebar, toolbar, status bar, clone and worktree dialogs
    views/        Local Changes and History views
    commit/       changed-files list and commit box
    log/          commit graph table and commit details
    diff/         diff viewer
    lfs/          Git LFS folder tree, local-data actions and settings
    files/        .gitignore, .gitattributes, .lfsconfig and README editor
    branches/     Branches popup and shared branch actions
    accounts/     hosting accounts dialogs
    remotes/      Manage Remotes dialog
    console/      Git console
    widgets/      split panes, buttons, menus, dialogs
test/             diff, graph, parser, hosting and widget tests (one runs real git)
```

## Tests

```bash
flutter test
```
