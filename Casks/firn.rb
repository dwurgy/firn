cask "firn" do
  version "1.0.1"
  sha256 "47d84ef1b3e7ab529299719f5b75ef30e5a36dae183f7575e3fca1dfe40b3da2"

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
