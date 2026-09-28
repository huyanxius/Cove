#!/bin/sh
# 只装 Command Line Tools、没有完整 Xcode 的机器上，Swift Testing 不在默认搜索路径里，
# 这里补上 framework 与 rpath；有 Xcode 的机器上这些路径不存在，直接走默认。
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$CLT/Frameworks/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test "$@"
