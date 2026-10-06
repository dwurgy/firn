// Finds Playwright: the project's own copy if there is one, otherwise the
// one installed globally (Claude's cloud workspace has it there).
const { execSync } = require('child_process');
const path = require('path');

try {
  module.exports = require('playwright');
} catch {
  const root = execSync('npm root -g').toString().trim();
  module.exports = require(path.join(root, 'playwright'));
}
