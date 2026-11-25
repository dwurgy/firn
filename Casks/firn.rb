cask "firn" do
  version "1.1.1"
  sha256 "6a1cc878f47af9371cca618a440f5b34959c8f0744c6b58bd2d4de4d114d8a22"

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
