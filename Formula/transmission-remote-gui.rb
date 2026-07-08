# Homebrew formula — builds and installs Transmission Remote GUI from source.
#
# Builds from source (no notarization needed: it compiles on the user's machine, runs locally).
# After installation the GUI can be launched with the `transmission-remote-gui` command.
#
# TO FILL IN after the v0.1.0 tag exists:
#   - sha256  → `curl -sL <url> | shasum -a 256`
#
# As a tap:  brew install epaxpax/tap/transmission-remote-gui
class TransmissionRemoteGui < Formula
  desc "Native SwiftUI macOS remote GUI for the Transmission BitTorrent daemon"
  homepage "https://github.com/epaxpax/transmission-remote-gui"
  url "https://github.com/epaxpax/transmission-remote-gui/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on macos: :sonoma   # macOS 14+

  def install
    system "swift", "build", "--configuration", "release",
           "--product", "TransmissionRemoteGUI", "--disable-sandbox"
    bin.install ".build/release/TransmissionRemoteGUI" => "transmission-remote-gui"
  end

  test do
    assert_predicate bin/"transmission-remote-gui", :exist?
  end
end
