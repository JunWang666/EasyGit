#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// WM_COPYDATA id for "open this folder" (payload: UTF-16 path, may be empty).
constexpr ULONG_PTR kOpenFolderMessage = 0x45470001;  // 'EG' 1

// One EasyGit window per executable. When an instance of this executable is
// already running, hands it the first command line argument (a folder to
// open), and returns true: the caller should exit.
bool ForwardToRunningInstance();

#endif  // RUNNER_SINGLE_INSTANCE_H_
