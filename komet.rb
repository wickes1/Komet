cask "komet" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_AFTER_RELEASE"

  url "https://github.com/wickes1/Komet/releases/download/v#{version}/Komet.dmg"
  name "Komet"
  desc "Minimal, lightning-fast application launcher for macOS"
  homepage "https://github.com/wickes1/Komet"

  depends_on macos: ">= :ventura"

  # Avoid conflict with homebrew-cask/komet (git commit editor)
  conflicts_with cask: "komet"

  app "Komet.app"

  caveats <<~EOS
    Komet is unsigned. If blocked by Gatekeeper:
    1. Go to System Settings → Privacy & Security
    2. Click "Open Anyway" next to the Komet warning

    Komet requires Accessibility permissions:
    System Settings → Privacy & Security → Accessibility → Enable Komet
  EOS

  zap trash: [
    "~/Library/Preferences/com.wickes1.komet.plist",
    "~/Library/Caches/com.wickes1.komet",
  ]
end
