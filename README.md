<!-- README.md is generated from README.Rmd. Edit the .Rmd, then run: Rscript -e 'knitr::knit("README.Rmd")' -->



# Keyword rules vs an LLM: classifying field-service job notes in R

My [field-service app](https://github.com/BrennanKM/field-service-client-directory) sorts free-text job notes ("cleared blackberries behind the shed, 3 loads to the dump") into five service categories so its Stats view can report revenue and $/hour by service line. It does that with a short list of keyword rules. Jobs get their service from a picker (Blackberry removal, Pressure washing, Junk removal, Dump run, Yard work, Other) or a free-text box. This project asks whether an LLM does the job better, what it gets wrong, and what it costs per job.

**Short answer:** on 300 synthetic job notes, the keyword rules got **73%** right and the LLM (claude-haiku-5-5) got **85%**. The rules are near-perfect on wording like the picker's (98%) and fall apart on shorthand, synonyms and typos (41%). The LLM handles that variation much better, but it has a blind spot of its own: it filed 32 of 75 blackberry jobs as general yard work, including notes that say "Blackberry removal" word for word. I rewrote the prompt once, adding three rules for close calls and six examples (prompt v2). That cut the blackberry mistake to 2 and raised the LLM to **94%**. It's an optimistic number, because I wrote v2 after reading v1's mistakes on these same notes.

The LLM costs about $0.17 to $0.23 per 1,000 notes and about 1.3 seconds of model time per note; the rules are free and take about 5.2 microseconds.

## Data

All 300 job notes are **synthetic**. No real client, address, phone number or job record is in this repo. `R/01_make_data.R` writes them from templates with a fixed seed, and each template carries its true category. [LABELING.md](LABELING.md) has the labeling rule and category definitions.


|True category          | Canonical| Variant| Total|
|:----------------------|---------:|-------:|-----:|
|Blackberry removal     |        49|      26|    75|
|Junk removal & hauling |        25|      35|    60|
|Other                  |        10|      20|    30|
|Pressure washing       |        43|      32|    75|
|Yard / outdoor work    |        41|      19|    60|

*Canonical* notes start from a picker name ("Pressure washing driveway", "Dump run, a couch"). *Variant* notes use shorthand, synonyms, combined jobs or a typo.

## Method

| | Keyword rules | LLM |
|---|---|---|
| What it is | `classifyService()` from the app, ported to R in [`R/keyword_classifier.R`](R/keyword_classifier.R). First matching regex wins. | claude-haiku-5-5, one call per note, via the Claude Code CLI in print mode with no tools ([`R/03_run_llm.R`](R/03_run_llm.R)). |
| Input | The note | The note, plus a system prompt. [Prompt v1](prompts/v1.txt) gives the five category definitions. [Prompt v2](prompts/v2.txt) adds three rules for close calls and six examples; see [Fixing the prompt](#fixing-the-prompt). |
| Check | [`R/02_check_port.R`](R/02_check_port.R) runs the original JavaScript on every note; the R port matches it on all 300. | Replies are matched to a category name; 1 of 600 didn't match. |

**Hybrid** rows are computed from the same predictions with no extra calls: use the keyword rules, and only call the LLM when the rules return `Other`.

## Results


|Classifier     | Accuracy| Macro F1| Canonical notes| Variant notes|
|:--------------|--------:|--------:|---------------:|-------------:|
|Keyword rules  |      73%|     0.71|             98%|           41%|
|LLM, prompt v1 |      85%|     0.86|             86%|           84%|
|LLM, prompt v2 |      94%|     0.92|             98%|           88%|
|Hybrid, v1     |      85%|     0.83|             97%|           68%|
|Hybrid, v2     |      87%|     0.85|             97%|           74%|

Both hybrids send 23% of notes to the LLM.

![Accuracy by wording style](figures/accuracy_by_style.png)

### Confusion matrices

![Confusion matrices](figures/confusion.png)

### Precision and recall by category


|Category               | Keyword rules, precision / recall| LLM, prompt v1, precision / recall| LLM, prompt v2, precision / recall|
|:----------------------|---------------------------------:|----------------------------------:|----------------------------------:|
|Blackberry removal     |                        100% / 70%|                         100% / 57%|                         100% / 97%|
|Pressure washing       |                         82% / 86%|                         98% / 100%|                         94% / 100%|
|Junk removal & hauling |                         80% / 63%|                         100% / 86%|                         100% / 83%|
|Yard / outdoor work    |                         80% / 70%|                         59% / 100%|                          92% / 96%|
|Other                  |                         31% / 73%|                          96% / 90%|                          76% / 86%|

![Precision and recall](figures/precision_recall.png)

## Where they disagree

This section compares the keyword rules with the LLM on prompt v1. The two gave different answers on 96 of 300 notes. The LLM was right on 62 of them, the keyword rules on 25, and both were wrong on 9.

**Why the keyword rules miss.** Each row below is one keyword that sent notes to the wrong category, with one example note.


|Keyword that fired  | Errors|Example note                            |True                   |Rules said             |
|:-------------------|------:|:---------------------------------------|:----------------------|:----------------------|
|`(nothing matched)` |     47|Cleaned moss off the siding             |Pressure washing       |Other                  |
|`yard`              |      9|bramble clearing in the side yard       |Blackberry removal     |Yard / outdoor work    |
|`bed`               |      6|planted shrubs in the front beds        |Yard / outdoor work    |Junk removal & hauling |
|`driveway`          |      5|Weeding by the driveway, Venmo          |Yard / outdoor work    |Pressure washing       |
|`deck`              |      4|Deck staining, two coats                |Yard / outdoor work    |Pressure washing       |
|`wash`              |      3|Window washing, inside and out, Venmo   |Other                  |Pressure washing       |
|`move`              |      2|removed ivy from the fence              |Yard / outdoor work    |Junk removal & hauling |
|`patio`             |      2|assembled patio furniture, paid cash    |Other                  |Pressure washing       |
|`pavers`            |      1|cleaned moss off the pavers             |Pressure washing       |Junk removal & hauling |
|`wood`              |      1|Took scrap wood to the transfer station |Junk removal & hauling |Yard / outdoor work    |

Two kinds of miss. 47 of the rules' 80 misses are notes no rule matched ("bramble", "berry vines", "PW", "moss"), so they fall to `Other`. The other 33 are a rule firing on the wrong word: place words like `yard`, `driveway`, `deck` and `patio` describe where the job was, not what was done, and plain substrings catch too much (`move` inside "removed", `bed` inside "flower beds" and "bedroom", `wash` in window washing). Because the rules run in order, a place word in an early rule wins over the real service in a later one.

**Where the LLM (prompt v1) misses.** Grouped by the mistake, with one example note each.


|True                   |LLM said            | Errors|Example note                                              |
|:----------------------|:-------------------|------:|:---------------------------------------------------------|
|Blackberry removal     |Yard / outdoor work |     32|Cleared blackberries in the backyard, 2 loads to the dump |
|Junk removal & hauling |Yard / outdoor work |      7|Pickup load to recycling, yard debris                     |
|Other                  |Yard / outdoor work |      2|Hung holiday ligths, quoted on site                       |
|Junk removal & hauling |Other               |      1|Took two old appliances to the transfer station, Venmo    |
|Other                  |Pressure washing    |      1|Window washing, inside and out                            |

The big one is blackberry work filed as yard work: 32 of 75 blackberry jobs, and 21 of the 49 that use the plain picker wording. The system prompt defines Blackberry removal as its own category, and the model still folded it into the broader one. It also tends to read "yard debris" as yard work when the job was hauling it away. The keyword rules never misfile a note that contains "blackberr", because that rule is checked first.

The full disagreement list is in [`data/disagreements.csv`](data/disagreements.csv).



## Fixing the prompt

Prompt v1 gave the model the five category definitions and nothing else. [Prompt v2](prompts/v2.txt) keeps those and adds:

- **Three rules for close calls:** blackberry clearing is its own service line, not a kind of yard work; taking something away is hauling even when it came from a yard; a place in the note says where the job was, not what was done.
- **Six examples,** one or two per category. None of them appear in the test notes (checked by string match), but I wrote them after seeing v1's mistakes, so they target exactly those mistakes.


|                         | Notes|
|:------------------------|-----:|
|Wrong on v1, right on v2 |    38|
|Right on v1, wrong on v2 |    13|
|Wrong on both            |     5|
|Right on both            |   244|

The blackberry fix worked: 32 misfiles became 2. But the change wasn't free. v2 broke 13 notes v1 had right, and its biggest new mistake is hauling jobs filed as `Other` (8 of 60). Most are jobs like "Took a busted treadmill to the transfer station" or "Removed two old appliances from the basement", where the note says what was moved but not the word "haul" or "junk". 1 v2 reply explained its answer instead of giving just the category name; it's counted as wrong.

**Where the LLM (prompt v2) still misses.**


|True                   |LLM said            | Errors|Example note                                        |
|:----------------------|:-------------------|------:|:---------------------------------------------------|
|Junk removal & hauling |Other               |      8|Removed two old appliances from the basement, Venmo |
|Other                  |Pressure washing    |      3|Window washing, inside and out, Venmo               |
|Blackberry removal     |Yard / outdoor work |      2|Cleared thorny vines in the backyard                |
|Junk removal & hauling |Yard / outdoor work |      2|Took yard debris to the transfer sation             |
|Other                  |Yard / outdoor work |      1|Fixed a gate latch                                  |
|Yard / outdoor work    |Pressure washing    |      1|Spread 4 yards of bark                              |
|Yard / outdoor work    |(not a category)    |      1|Weeding in the side yard, 2 guys                    |

With v2, the hybrid (87%) now trails the LLM alone. Once the LLM handles blackberry work, the hybrid's weak spot is that it trusts the rules whenever any keyword matches, including the 33 notes where the rules matched the wrong word.

## Cost and latency


|                              | Keyword rules|           LLM, prompt v1|           LLM, prompt v2|
|:-----------------------------|-------------:|------------------------:|------------------------:|
|Cost per 1,000 notes          |            $0|                    $0.23|                    $0.17|
|Median time per note          |        5.2 µs| 8.1 s (API alone: 1.3 s)| 8.6 s (API alone: 1.7 s)|
|90th percentile time per note |              | 9.1 s (API alone: 1.9 s)|  10 s (API alone: 3.1 s)|
|Tokens per call (in / out)    |           n/a|                1154 / 11|                1528 / 10|
|Runs offline                  |           Yes|                       No|                       No|

LLM cost is the per-call figure the CLI reports at API prices, summed over 300 calls per prompt. Input tokens include context the CLI adds on top of my prompt, so a direct API call with the same prompt would send fewer tokens and cost less. Wall-clock time is for one CLI call with 4 calls running at once, including process start; "API alone" is the time the CLI reports waiting on the model. Prompt v2 is longer, yet the CLI reported a lower cost per call; I didn't save the token-cache breakdown that would explain why. Keyword time is the R port, averaged over 600,000 classifications.

## What I'd do with this

- **For jobs logged from the picker,** the rules are the right tool: close to perfect, free and instant. The LLM on prompt v1 was worse on these notes because of the blackberry mistake, and prompt v2 only tied the rules.
- **For jobs typed by hand,** the rules misfile without any warning, and that skews the revenue-by-service and $/hour charts the app exists to produce. The cheapest fix is word boundaries (`\bmove\b`, `\bbeds?\b`), dropping place words from the rules, and a few synonyms.
- **An LLM isn't a drop-in upgrade.** With the first prompt it was better overall but wrong in a consistent direction on the business's main service line. That's the kind of error that moves a revenue-by-service chart, and it only showed up because the results were checked against labels.
- **Prompt fixes trade errors, they don't just remove them.** v2 fixed 38 notes and broke 13. Checking only the notes you set out to fix would have missed the new hauling mistake.
- **What I'd ship:** the rules for jobs logged from the picker, and the LLM with prompt v2 for typed notes, after a test on fresh notes it was never tuned on. The 94% won't hold up exactly on notes it hasn't seen.

## Limits

- The notes are synthetic, so the accuracy numbers describe how each classifier handles this kind of variation, not how often that variation shows up in real job logs.
- I wrote both the templates and the labels. The LLM was given the same category definitions I labeled with; the keyword rules were written earlier from real notes. The LLM has the easier job by design.
- Prompt v2 was written after reading v1's mistakes on the same 300 notes, so its score is an upper bound. A fair test needs new notes written without looking at v2's results.
- One model, one run per prompt, 300 notes. Differences of a few points are within noise.

## Reproduce

Needs R (dplyr, tidyr, purrr, readr, stringr, ggplot2, scales, jsonlite, withr, knitr), Node.js for the port check, and a logged-in Claude Code CLI for the LLM step.

```sh
Rscript R/01_make_data.R     # write data/jobs.csv
Rscript R/02_check_port.R    # R port vs the original JavaScript
Rscript R/03_run_llm.R       # LLM labels, prompt v1, cached in data/llm_predictions.csv
PROMPT_VERSION=v2 Rscript R/03_run_llm.R   # prompt v2, cached in data/llm_predictions_v2.csv
Rscript -e 'knitr::knit("README.Rmd")'
```

Step 3 is the only one that calls a model; the cached predictions are committed, so the README rebuilds without it.
