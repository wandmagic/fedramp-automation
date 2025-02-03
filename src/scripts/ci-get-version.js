// get-version.mjs
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Function to find repository root (where package.json lives)
function findRepoRoot(startDir) {
  let currentDir = startDir;
  while (currentDir !== '/') {
    const packagePath = join(currentDir, 'package.json');
    if (existsSync(packagePath)) {
      return currentDir;
    }
    currentDir = dirname(currentDir);
  }
  throw new Error('Could not find repository root (no package.json found)');
}

// Get repo root
const repoRoot = findRepoRoot(__dirname);

// Get source, name and default version from command line arguments
const [source, name, defaultVersion = '0.5.0'] = process.argv.slice(2);

if (!source || !name) {
  console.error('Usage: node ci-get-version.js [package|tool] [name] [defaultVersion]');
  process.exit(1);
}

try {
  if (source === 'package') {
    const packagePath = join(repoRoot, 'package.json');
    const packageJson = JSON.parse(readFileSync(packagePath, 'utf8'));
    const version = packageJson.dependencies?.[name] || defaultVersion;
    console.log(version)
  } else if (source === 'tool') {
    const toolPath = join(repoRoot, '.tool-versions');
    const content = readFileSync(toolPath, 'utf8');
    const lines = content.split('\n').map(line => line.trim());
    const matchingLines = lines.filter(line => line.startsWith(name));
    const version = matchingLines[0]?.split(/\s+/)[1] || defaultVersion;
    console.log(version)
  } else {
    console.error('Invalid source. Use "package" or "tool"');
    process.exit(1);
  }
} catch (error) {
  console.log(defaultVersion);
}