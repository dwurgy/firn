cask "firn" do
  version "1.0.0"
  sha256 "7e65cf21a0fc5324870d60ef71b80714ec35435da4c4bcd25760d3400e16b987"

  url "https://github.com/dwurgy/firn/releases/download/v#{version}/Firn-#{version}.dmg"
  name "Firn"
  desc "Quiet, minimalist web browser"
  homepage "https://firnbrowser.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Firn.app"
end
