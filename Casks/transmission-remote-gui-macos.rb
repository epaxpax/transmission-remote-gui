cask "transmission-remote-gui-macos" do
  version "0.1.11"
  sha256 "5c6e55f86871289e96098688da068d1d4e0fe5973c2641ba82959ab3f6dd7125"

  url "https://github.com/epaxpax/transmission-remote-gui/releases/download/v#{version}/Transmission.Remote.GUI.app.zip"
  name "Transmission Remote GUI"
  desc "Native SwiftUI remote GUI for the Transmission BitTorrent daemon"
  homepage "https://github.com/epaxpax/transmission-remote-gui"

  depends_on macos: :sonoma

  app "Transmission Remote GUI.app"

  # Ad-hoc signed (not notarized): strip the download quarantine so Gatekeeper
  # does not block launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Transmission Remote GUI.app"],
        writable_paths: ["Transmission Remote GUI.app"],
        writable_base:  :appdir
  end

  caveats <<~EOS
    Transmission Remote GUI is ad-hoc signed (not notarized). If macOS still blocks it,
    right-click it in Applications and choose Open.
  EOS
end
