#!/usr/bin/env node

import fs from 'fs/promises';
import path from 'path';
import { performance } from 'perf_hooks';
import { fileURLToPath } from 'url';
import { validateDocument } from 'oscal';
import { resolve } from 'path';
import { JSDOM } from 'jsdom';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Example SSP to validate against
const EXAMPLE_SSP = path.join(__dirname, '../content/rev5/examples/ssp/xml/fedramp-ssp-example.oscal.xml');

// Directory containing reporting files
const REPORTS_DIR = path.join(__dirname, '../../reports');

// Directory containing constraint files
const CONSTRAINTS_DIR = path.join(__dirname, '../validations/constraints');

// Directory to store individual constraints
const EXPLODED_DIR = path.join(__dirname, '../validations/constraints/exploded');

async function validateWithConstraint(sspPath, constraintPath) {
  const start = performance.now();
  
  try {
    const { isValid, log } = await validateDocument(
      resolve(sspPath),
      {
        quiet: true,
        extensions: [resolve(constraintPath)]
      }
    );
    
    const end = performance.now();
    return {
      time: end - start,
      success: isValid,
      log
    };
  } catch (err) {
    throw new Error(`Validation error: ${err.message}`);
  }
}

async function extractConstraints(xmlPath) {
  const content = await fs.readFile(xmlPath, 'utf-8');
  const dom = new JSDOM(content, { contentType: "text/xml" });
  const doc = dom.window.document;

  // Get all contexts
  const contexts = doc.getElementsByTagName('context');
  const constraints = [];

  for (const context of contexts) {
    // Get metapath, variables, and indexes
    const metapaths = Array.from(context.getElementsByTagName('metapath')).map(m => m.getAttribute('target'));
    const variables = Array.from(context.getElementsByTagName('let')).map(v => ({
      var: v.getAttribute('var'),
      expression: v.getAttribute('expression')
    }));
    const indexes = Array.from(context.getElementsByTagName('index')).map(idx => ({
      name: idx.getAttribute('name'),
      target: idx.getAttribute('target'),
      formalName: idx.getElementsByTagName('formal-name')[0]?.textContent,
      description: idx.getElementsByTagName('description')[0]?.textContent,
      keyField: idx.getElementsByTagName('key-field')[0]?.getAttribute('target')
    }));

    // Get individual constraints
    const constraintElements = context.getElementsByTagName('constraints')[0];
    if (!constraintElements) continue;

    // Process each constraint type (expect, matches, etc.)
    for (const child of constraintElements.children) {
      if (child.tagName === 'let') continue; // Skip variable declarations

      const id = child.getAttribute('id');
      if (!id) continue;

      // Create XML for this individual constraint
      const constraintXml = `<?xml version="1.0" encoding="UTF-8"?>
<metaschema-meta-constraints xmlns="http://csrc.nist.gov/ns/oscal/metaschema/1.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <context>
        ${metapaths.map(mp => `<metapath target="${mp}"/>`).join('\n        ')}
        <constraints>
            ${variables.map(v => `<let var="${v.var}" expression="${v.expression}"/>`).join('\n            ')}
            ${indexes.map(idx => `<index name="${idx.name}" target="${idx.target}">
                <formal-name>${idx.formalName || ''}</formal-name>
                <description>${idx.description || ''}</description>
                <key-field target="${idx.keyField}"/>
            </index>`).join('\n            ')}
            ${child.outerHTML.replace(' xmlns="http://csrc.nist.gov/ns/oscal/metaschema/1.0"', '')}
        </constraints>
    </context>
</metaschema-meta-constraints>`;

      constraints.push({
        id,
        xml: constraintXml
      });
    }
  }

  return constraints;
}

async function main() {
  try {
    console.log('Finding constraint files...');
    
    // Create exploded directory if it doesn't exist
    await fs.mkdir(EXPLODED_DIR, { recursive: true });

    // Process main constraints file
    const mainConstraintsFile = path.join(CONSTRAINTS_DIR, 'fedramp-external-constraints.xml');
    const constraints = await extractConstraints(mainConstraintsFile);
    
    console.log(`Found ${constraints.length} individual constraints\n`);

    // Write individual constraint files
    for (const constraint of constraints) {
      const filePath = path.join(EXPLODED_DIR, `${constraint.id}.xml`);
      await fs.writeFile(filePath, constraint.xml);
    }

    console.log('Testing constraints...');
    const results = [];
    
    // Test each constraint
    for (const constraint of constraints) {
      const constraintPath = path.join(EXPLODED_DIR, `${constraint.id}.xml`);
      process.stdout.write(`Testing ${constraint.id}... `);
      
      try {
        const result = await validateWithConstraint(EXAMPLE_SSP, constraintPath);
        results.push({
          constraint: constraint.id,
          time: result.time,
          success: result.success,
          log: result.log
        });
        console.log(`${result.time.toFixed(2)}ms ${result.success ? '✓' : '✗'}`);
      } catch (err) {
        console.log('Error!');
        console.error(`  ${err.message}`);
        results.push({
          constraint: constraint.id,
          time: null,
          success: false,
          error: err.message
        });
      }
    }

    // Sort results by time
    results.sort((a, b) => (b.time || 0) - (a.time || 0));

    // Generate markdown table
    let markdown = '# Constraint Performance Results\n\n';
    markdown += '| Constraint ID | Time (ms) | Status |\n';
    markdown += '|---------------|-----------|--------|\n';

    for (const result of results) {
      const status = result.time === null ? '❌' : (result.success ? '✓' : '✗');
      let validationInfo = '';            
      markdown += `| ${result.constraint} | ${result.time ? result.time.toFixed(2) : 'N/A'} | ${status} |\n`;
    }

    // Calculate statistics
    const successfulTimes = results.filter(r => r.time !== null).map(r => r.time);
    if (successfulTimes.length > 0) {
      const total = successfulTimes.reduce((a, b) => a + b, 0);
      const avg = total / successfulTimes.length;
      const max = Math.max(...successfulTimes);
      const min = Math.min(...successfulTimes);

      markdown += '\n## Statistics\n\n';
      markdown += `- Total time: ${total.toFixed(2)}ms\n`;
      markdown += `- Average time: ${avg.toFixed(2)}ms\n`;
      markdown += `- Max time: ${max.toFixed(2)}ms\n`;
      markdown += `- Min time: ${min.toFixed(2)}ms\n`;
      markdown += `- Success rate: ${successfulTimes.length}/${results.length} (${((successfulTimes.length/results.length)*100).toFixed(1)}%)\n`;
    }

    // Write results to markdown file
    await fs.writeFile(path.join(EXPLODED_DIR, 'results.md'), markdown);

    // Copy results file to parent directory before deleting exploded directory
    await fs.copyFile(path.join(EXPLODED_DIR, 'results.md'), path.join(REPORTS_DIR, 'constraints-performance.md'));
    console.log('\nResults written to '+path.resolve(REPORTS_DIR, 'constraints-performance.md'));
    
    // Delete exploded directory
    await fs.rm(EXPLODED_DIR, { recursive: true, force: true });
    console.log('Cleaned up exploded directory');

  } catch (err) {
    console.error('Fatal error:', err);
    process.exit(1);
  }
}

main();
