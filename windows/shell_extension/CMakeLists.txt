# "Open in EasyGit" Explorer context menu handler (see easygit_shell.cpp).
add_library(easygit_shell SHARED
  "easygit_shell.cpp"
  "easygit_shell.def"
)
apply_standard_settings(easygit_shell)
target_compile_definitions(easygit_shell PRIVATE UNICODE _UNICODE NOMINMAX)
target_link_libraries(easygit_shell PRIVATE shlwapi.lib shell32.lib ole32.lib runtimeobject.lib)

# Installed by the top-level CMakeLists.txt, once the install prefix is set.
