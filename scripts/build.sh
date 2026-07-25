#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DATA_DIR="${PROJECT_DIR}/DerivedData"

echo "正在生成 Xcode 工程…"
cd "${PROJECT_DIR}"
xcodegen generate

echo "正在运行单元测试…"
xcodebuild \
  -project FinderTerminal.xcodeproj \
  -scheme FinderTerminal \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  test

echo "正在构建 Release 应用…"
xcodebuild \
  -project FinderTerminal.xcodeproj \
  -scheme FinderTerminal \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build

echo "构建完成：${DERIVED_DATA_DIR}/Build/Products/Release/FinderTerminal.app"
