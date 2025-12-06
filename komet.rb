cask "komet" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_AFTER_RELEASE"

  url "https://github.com/wickes1/Komet/releases/download/v#{version}/Komet.dmg"
  name "Komet"
  desc "Minimal, lightning-fast application launcher for macOS"
  homepage "https://github.com/wickes1/Komet"

  depends_on macos: ">= :ventura"

  app "Komet.app"

  postflight do
    # Remove quarantine flag to bypass Gatekeeper for unsigned app
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Komet.app"],
                   sudo: false

    # Remind user about accessibility permissions
    ohai "Komet requires Accessibility permissions to work."
    ohai "Go to System Settings > Privacy & Security > Accessibility"
    ohai "and enable Komet."
  end

  zap trash: [
    "~/Library/Preferences/com.wickes1.komet.plist",
    "~/Library/Caches/com.wickes1.komet",
  ]
end
