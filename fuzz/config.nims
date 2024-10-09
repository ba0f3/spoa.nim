switch("path", "$projectDir/../src")

let cc = "afl-clang-fast"
switch("gcc.linkerexe", cc)
switch("gcc.exe", cc)
switch("gcc.path", "/usr/bin")

--debugger:native
--define:release
--define:danger