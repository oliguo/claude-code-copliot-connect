# brew/copilot-api-connect.rb
# Local Homebrew formula for copilot-api-connect.
#
# Install via local tap:
#   brew tap oliguo/copilot-api-connect /path/to/claude-code-copliot-connect
#   brew install copilot-api-connect
#
# After install, run:
#   copilot-api auth
#   copilot-api-connect-install

class CopilotApiConnect < Formula
  desc "Install copilot-api as a macOS LaunchAgent for Claude Code"
  homepage "https://github.com/oliguo/claude-code-copliot-connect"
  version "1.0.0"
  license "MIT"

  # Local tap — no URL/sha256 needed; Homebrew resolves from the tap directory
  head do
    url "https://github.com/oliguo/claude-code-copliot-connect.git", branch: "main"
  end

  depends_on :macos
  depends_on "node"

  def install
    # Install the launchd wrapper script
    bin.install "scripts/copilot-api-start" => "copilot-api-start"
    # Install the main installer (renamed to avoid clash with system 'install')
    bin.install "install.sh" => "copilot-api-connect-install"
  end

  def caveats
    <<~EOS
      Before running the installer, authenticate with GitHub Copilot:
        copilot-api auth

      Then run the installer:
        copilot-api-connect-install

      Other options:
        copilot-api-connect-install --dry-run     # preview without changes
        copilot-api-connect-install --force       # update token after re-auth
        copilot-api-connect-install --uninstall   # remove LaunchAgent

      When your token expires:
        copilot-api auth && copilot-api-connect-install --force
    EOS
  end

  test do
    # Verify scripts are installed and executable
    assert_predicate bin/"copilot-api-start", :executable?
    assert_predicate bin/"copilot-api-connect-install", :executable?
    # Verify bash syntax
    system "bash", "-n", bin/"copilot-api-start"
    system "bash", "-n", bin/"copilot-api-connect-install"
  end
end
