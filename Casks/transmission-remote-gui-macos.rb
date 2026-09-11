# Homebrew cask (reference copy; the installable tap lives at epaxpax/homebrew-tap).
# Install:  brew install --cask epaxpax/tap/transmission-remote-gui-macos
cask "transmission-remote-gui-macos" do
  version "0.1.5"
  sha256 "521d15b63013747ed322c522db3123c2e1e624a603f0e8c79fc2dfce136d68a7"

  url "https://github.com/epaxpax/transmission-remote-gui/releases/download/v#{version}/Transmission.Remote.GUI.app.zip",
      verified: "github.com/epaxpax/transmission-remote-gui/"
  name "Transmission Remote GUI"
  desc "Native SwiftUI macOS remote GUI for the Transmission BitTorrent daemon"
  homepage "https://github.com/epaxpax/transmission-remote-gui"

  app "Transmission Remote GUI.app"

  # Ad-hoc signed (not notarized): strip the download quarantine so Gatekeeper allows launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Transmission Remote GUI.app"]
  end
end
