#!/usr/bin/env swift
// Design/cats/sitting.svg → AppIcon.icns.
//
// 사용법: swift scripts/make-icon.swift [출력.icns]   (기본값: dist/AppIcon.icns)
//
// sitting.svg 는 `#FUR` / `#FURDARK` / `#FURLIGHT` 플레이스홀더를 들고 있다(런타임에
// CatShapes.palette 가 채운다). 아이콘은 정적이라 0번 팔레트 색을 직접 박아 넣는다 —
// 그 세 색의 정본은 scripts/generate-cat-art.sh 의 FUR / FUR_DARK / FUR_LIGHT 이고
// 여기 값은 거기서 베낀 것이다. 거기를 바꾸면 여기도 같이 바꾼다.
//
// 흐름: 색 치환 → 임시 SVG → NSImage(SVG, macOS 11+) → 알파 경계상자 측정 →
//       각 크기 캔버스에 고양이를 가운데·8% 여백으로 벡터 렌더 → .iconset → iconutil.

import AppKit
import Foundation

// scripts/generate-cat-art.sh 의 FUR / FUR_DARK / FUR_LIGHT (팔레트 0번, 원본 갈회색)
let fur = "#7D6C62"
let furDark = "#66584F"
let furLight = "#A09084"

/// 캔버스 한 변 대비 여백 비율. 고양이가 아이콘 격자에 너무 꽉 차지 않게.
let paddingRatio = 0.08
/// 경계상자를 재는 마스터 렌더 해상도.
let probeSize = 1024
/// iconset 이 요구하는 (파일 이름, 픽셀 크기) 목록. 16/32/64/128/256/512/1024 를 모두 덮는다.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

// MARK: - 경로

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()    // scripts/
    .deletingLastPathComponent()    // 레포 루트
let source = repoRoot.appendingPathComponent("Design/cats/sitting.svg")
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent("dist/AppIcon.icns")

guard FileManager.default.fileExists(atPath: source.path) else {
    fail("원본이 없다: \(source.path)")
}

// MARK: - 최신이면 건너뛴다 (멱등)

/// 입력이 셋이다: 원본 SVG, 팔레트 정본(generate-cat-art.sh — 여기 색을 바꾸면 아이콘도
/// 바뀌어야 한다), 그리고 이 스크립트. 셋 다 결과물보다 낡았으면 다시 만들지 않는다.
func isUpToDate() -> Bool {
    let fm = FileManager.default
    guard let out = try? fm.attributesOfItem(atPath: output.path)[.modificationDate] as? Date
    else { return false }
    let inputs = [
        source,
        repoRoot.appendingPathComponent("scripts/generate-cat-art.sh"),
        URL(fileURLWithPath: CommandLine.arguments[0]),
    ]
    for input in inputs {
        guard let stamp = try? fm.attributesOfItem(atPath: input.path)[.modificationDate] as? Date
        else { return false }
        if stamp > out { return false }
    }
    return true
}

if isUpToDate() {
    print("make-icon: 최신 — \(output.lastPathComponent) 를 그대로 쓴다")
    exit(0)
}

// MARK: - 색 치환

guard var svg = try? String(contentsOf: source, encoding: .utf8) else {
    fail("원본을 읽지 못했다: \(source.path)")
}
// 긴 이름부터 바꾼다 — "#FUR" 을 먼저 바꾸면 "#FURDARK" 가 "<색>DARK" 로 깨진다.
svg = svg.replacingOccurrences(of: "#FURDARK", with: furDark)
svg = svg.replacingOccurrences(of: "#FURLIGHT", with: furLight)
svg = svg.replacingOccurrences(of: "#FUR", with: fur)

let temp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("claude-cats-icon-\(ProcessInfo.processInfo.processIdentifier).svg")
do { try svg.write(to: temp, atomically: true, encoding: .utf8) } catch {
    fail("임시 SVG 를 쓰지 못했다: \(error.localizedDescription)")
}
defer { try? FileManager.default.removeItem(at: temp) }

guard let art = NSImage(contentsOf: temp) else {
    fail("SVG 를 NSImage 로 못 읽었다 (macOS 11+ 필요): \(temp.path)")
}

// MARK: - 렌더

/// 투명 캔버스에 `draw` 를 그린 비트맵.
func canvas(_ pixels: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fail("비트맵을 만들지 못했다 (\(pixels)px)") }
    rep.size = NSSize(width: pixels, height: pixels)

    let saved = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.current = saved
    return rep
}

/// 그림에서 실제로 칠해진 부분의 경계상자. 단위 정사각형(왼쪽 아래 원점) 좌표로 돌려준다.
/// SVG 여백까지 여백으로 세면 고양이가 아이콘 안에서 작고 삐뚤어 보인다.
func contentBounds() -> (x: Double, y: Double, width: Double, height: Double) {
    let master = canvas(probeSize) {
        art.draw(in: NSRect(x: 0, y: 0, width: probeSize, height: probeSize))
    }
    guard let data = master.bitmapData else { fail("마스터 렌더의 픽셀을 못 읽었다") }
    let stride = master.bytesPerRow
    let alphaOffset = 3   // RGBA

    var minX = probeSize, minY = probeSize, maxX = -1, maxY = -1
    for row in 0..<probeSize {
        let base = row * stride
        for column in 0..<probeSize where data[base + column * 4 + alphaOffset] > 8 {
            if column < minX { minX = column }
            if column > maxX { maxX = column }
            if row < minY { minY = row }
            if row > maxY { maxY = row }
        }
    }
    guard maxX >= minX, maxY >= minY else { fail("렌더 결과가 전부 투명하다") }

    let side = Double(probeSize)
    let width = Double(maxX - minX + 1) / side
    let height = Double(maxY - minY + 1) / side
    // 비트맵은 위가 0행이고 드로잉 좌표는 아래가 0이다. y 를 뒤집는다.
    return (Double(minX) / side, 1 - Double(maxY + 1) / side, width, height)
}

let bounds = contentBounds()

let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
    fail("출력 디렉터리를 못 만들었다: \(error.localizedDescription)")
}

for variant in variants {
    let side = Double(variant.pixels)
    let content = side * (1 - 2 * paddingRatio)
    // 그림 전체를 k×k 로 그리면 경계상자는 k*width × k*height 가 된다. 그 긴 변을
    // 여백 뺀 상자에 맞추고, 경계상자 중심이 캔버스 중심에 오도록 원점을 민다.
    let k = content / max(bounds.width, bounds.height)
    let originX = side / 2 - k * (bounds.x + bounds.width / 2)
    let originY = side / 2 - k * (bounds.y + bounds.height / 2)

    let rep = canvas(variant.pixels) {
        art.draw(in: NSRect(x: originX, y: originY, width: k, height: k))
    }
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("PNG 인코딩 실패: \(variant.name)")
    }
    do {
        try png.write(to: iconset.appendingPathComponent(variant.name))
    } catch {
        fail("\(variant.name) 을 쓰지 못했다: \(error.localizedDescription)")
    }
}

// MARK: - iconutil

/// `command -v iconutil` 과 같은 규칙 — PATH 를 앞에서부터 훑어 실행 가능한 첫 항목.
/// 경로를 박아 두면 Xcode 툴체인이나 다른 SDK 의 iconutil 을 쓰는 환경을 무시하게 된다.
func findIconutil() -> URL? {
    let fm = FileManager.default
    let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
        let candidate = URL(fileURLWithPath: String(directory))
            .appendingPathComponent("iconutil")
        if fm.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    return nil
}

guard let iconutilURL = findIconutil() else {
    fail("iconutil 을 PATH 에서 못 찾았다")
}

let iconutil = Process()
iconutil.executableURL = iconutilURL
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
do { try iconutil.run() } catch {
    fail("iconutil 실행 실패: \(error.localizedDescription)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil 이 \(iconutil.terminationStatus) 로 끝났다")
}

try? FileManager.default.removeItem(at: iconset)
print("make-icon: 생성 \(output.path)")
