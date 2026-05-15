import Foundation

/// `solcito upgrade` — fetches the latest release tag from GitHub, compares
/// it against the version baked into this binary, and re-runs the canonical
/// `install.sh` to download + verify + replace the binary. Reuses the same
/// installer so any future polish there benefits this command too.
func runUpgrade() async {
    print()
    print("  \(Tone.heading("Checking for updates…"))")

    let latestTag: String
    do {
        latestTag = try await fetchLatestTag()
    } catch {
        die("Couldn't reach github.com: \(error)")
    }

    let currentTag = "v\(Version.current)"
    print("  \(Tone.subtle("Current \(currentTag)  →  Latest \(latestTag)"))")
    print()

    if !isNewerVersion(latestTag, than: currentTag) {
        print("  \(Tone.ok("✓ You're already on the latest version."))")
        print()
        return
    }

    print("  \(Tone.heading("Upgrading…"))")
    print()

    // Run the canonical installer. Inherits stdout/stderr so its colored
    // step log appears in our terminal as-is; inherits stdin so a sudo
    // prompt (only used for /usr/local/bin installs) still works.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = [
        "-c",
        "curl -fsSL https://raw.githubusercontent.com/lintuxt/solcito/main/install.sh | sh",
    ]
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        die("Couldn't run the installer: \(error)")
    }
    guard task.terminationStatus == 0 else {
        die("Installer exited with status \(task.terminationStatus).")
    }

    print()
    print("  \(Tone.ok("✓ Upgrade complete.")) Run `solcito version` to confirm.")
    print()
}

private func fetchLatestTag() async throws -> String {
    let url = URL(string: "https://api.github.com/repos/lintuxt/solcito/releases/latest")!
    var req = URLRequest(url: url)
    req.setValue("solcito-cli", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: req)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let tag = obj?["tag_name"] as? String, !tag.isEmpty else {
        throw NSError(domain: "Upgrade", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "`tag_name` missing from GitHub response"])
    }
    return tag
}

/// Trivial semver compare on `vX.Y.Z` strings. Lexicographic on
/// components after splitting; missing components count as 0. Doesn't
/// understand pre-release suffixes like `-rc1` (good enough for us).
private func isNewerVersion(_ a: String, than b: String) -> Bool {
    let ap = parts(of: a)
    let bp = parts(of: b)
    for i in 0..<max(ap.count, bp.count) {
        let av = i < ap.count ? ap[i] : 0
        let bv = i < bp.count ? bp[i] : 0
        if av != bv { return av > bv }
    }
    return false
}

private func parts(of v: String) -> [Int] {
    let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
    return trimmed.split(separator: ".").compactMap { Int($0) }
}
