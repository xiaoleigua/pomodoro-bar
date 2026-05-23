# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 沟通语言

永远使用中文与用户沟通。

## 项目概述

番茄钟应用，包含网页版和 macOS 原生菜单栏版。

## 构建与运行

```bash
bash build.sh                  # 编译 macOS .app
open ./build/PomodoroBar.app   # 启动
killall PomodoroBar            # 停止
```

## 架构

两个版本各自独立，不共享代码：

- `pomodoro.html` — 网页版，内联 CSS/JS，零依赖，浏览器打开
- `PomodoroBar.swift` — macOS 菜单栏版，Swift + AppKit，`swiftc` 编译
  - `PomodoroModel`：计时状态、模式切换、每日计数持久化（UserDefaults）
  - `RingView`：CAShapeLayer 环形进度条
  - `PomodoroViewController`：NSPopover 内容面板
  - `AppDelegate`：NSStatusBar 菜单栏项，左键面板/右键退出
- `build.sh` — 编译 + 创建 .app bundle + ad-hoc 签名
