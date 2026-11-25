cask "firn" do
  version "1.1.0"
  sha256 "d6ca1d991f6c9720e33ff56e8da49f68db39eb75d3c0bda6f0361bea6305b51b"

  url "https://github.com/dwurgy/firn/releases/download/v#{version}/Firn-#{version}.dmg"
  name "Firn"
  desc "Calm, minimalist web browser"
  homepage "https://firnbrowser.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Firn.app"
end
