# How the true labels were set

Every job description in `data/jobs.csv` is synthetic. It was written from a template, and the template carries the true category. No real job record was used.

**Rule:** the true category is the main service the job was billed for. A note that mentions a second task ("cleared blackberries, 2 loads to the dump") still belongs to the main service.

| Category | Covers |
|---|---|
| Blackberry removal | Clearing blackberry or other bramble and invasive berry vines |
| Pressure washing | Pressure, power or soft washing of hard surfaces, roofs, siding or fences, including moss and algae cleaning |
| Junk removal & hauling | Hauling away junk, debris, furniture or appliances; dump runs; cleanouts |
| Yard / outdoor work | Weeding, mulch and bark, mowing, pruning, planting, staining, firewood, stumps, digging |
| Other | Indoor work, small repairs, quote visits with no work done |

These five names are the ones `classifyService()` returns in the app, including its fallback `Other`.

**Styles.** Each row is tagged:
- `canonical`: written the way the app's service picker writes it ("Pressure washing driveway", "Junk removal, a couch").
- `variant`: shorthand, synonyms, combined jobs, or a typo ("PW siding", "bramble clearing", "Mulched the flower beds").

About 8% of rows get one typo, 20% get a short tail like ", paid cash", and 25% are lowercased. A row with a typo counts as `variant`.

The LLM is given the same category definitions as the table above. The keyword rules weren't written from this table; they were written from the job notes the app held at the time. That's a real advantage for the LLM, and it's the trade the comparison is about: one side reads a written spec, the other side encodes a spec in regexes.
