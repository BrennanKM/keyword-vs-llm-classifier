// classifyService() copied verbatim from BrennanKM/field-service-client-directory index.html (Stats view).
function classifyService(s) {
  const t = (s||'').toLowerCase();
  if (/blackberr/.test(t)) return 'Blackberry removal';
  if (/pressure|driveway|patio|deck|sidewalk|walkway|wash/.test(t)) return 'Pressure washing';
  if (/junk|haul|dump|move|pavers|furniture|bed/.test(t)) return 'Junk removal & hauling';
  if (/yard|bark|weed|chop|wood|seaside|outdoor|stain|post|fig/.test(t)) return 'Yard / outdoor work';
  return 'Other';
}

// Reads one description per line on stdin, prints one label per line.
const lines = require('fs').readFileSync(0, 'utf8').split('\n');
if (lines[lines.length - 1] === '') lines.pop();
process.stdout.write(lines.map(classifyService).join('\n') + '\n');
