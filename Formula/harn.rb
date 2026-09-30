class Harn < Formula
  desc "One command for any AI coding harness: subscription, gateway or local model"
  homepage "https://github.com/dean-harel/harn"
  url "https://github.com/dean-harel/harn.git",
      tag: "v0.1.0" # x-release-please-version
  license "MIT"
  head "https://github.com/dean-harel/harn.git", branch: "main"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/harn --version")
    assert_match "usage: harn", shell_output("#{bin}/harn --help")
  end
end
