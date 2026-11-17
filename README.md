<!-- README.md is generated from README.Rmd. Edit the .Rmd, then run: Rscript -e 'knitr::knit("README.Rmd")' -->



# Keyword rules vs an LLM: classifying field-service job notes in R

My [field-service app](https://github.com/BrennanKM/field-service-client-directory) sorts free-text job notes ("cleared blackberries behind the shed, 3 loads to the dump") into five service categories so its Stats view can report revenue and $/hour by service line. It does that with a short list of keyword rules. Jobs get their service from a picker (Blackberry removal, Pressure washing, Junk removal, Dump run, Yard work, Other) or a free-text box. This project asks whether an LLM does the job better, what it gets wrong, and what it costs per job.

**Short answer:** on 300 synthetic job notes, the keyword rules got **73%** right and the LLM (claude-haiku-5-5) got **85%**. The rules are near-perfect on wording like the picker's (98%) and fall apart on shorthand, synonyms and typos (41%). The LLM handles that variation much better, but it has a blind spot of its own: it filed 32 of 75 blackberry jobs as general yard work, including notes that say "Blackberry removal" word for word. A **hybrid** that uses the rules first and calls the LLM only when the rules give up scored **85%** while calling the LLM on 23% of notes.

The LLM costs about $0.23 per 1,000 notes and about 1.3 seconds of model time per note; the rules are free and take about 4 microseconds.

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
| Input | The note | The note, plus a system prompt with the five category definitions |
| Check | [`R/02_check_port.R`](R/02_check_port.R) runs the original JavaScript on every note; the R port matches it on all 300. | Replies are matched to a category name; 0 of 300 didn't match. |

A third column, **Hybrid**, is computed from the same predictions with no extra calls: use the keyword rules, and only call the LLM when the rules return `Other`.

## Results


|Classifier    | Accuracy| Macro F1| Canonical notes| Variant notes|
|:-------------|--------:|--------:|---------------:|-------------:|
|Keyword rules |      73%|     0.71|             98%|           41%|
|LLM           |      85%|     0.86|             86%|           84%|
|Hybrid        |      85%|     0.83|             97%|           68%|

The Hybrid sends 23% of notes to the LLM.

![Accuracy by wording style](figures/accuracy_by_style.png)

### Confusion matrices

![Confusion matrices](figures/confusion.png)

### Precision and recall by category


|Category               | Keyword precision| Keyword recall| LLM precision| LLM recall|
|:----------------------|-----------------:|--------------:|-------------:|----------:|
|Blackberry removal     |              100%|            70%|          100%|        57%|
|Pressure washing       |               82%|            86%|           98%|       100%|
|Junk removal & hauling |               80%|            63%|          100%|        86%|
|Yard / outdoor work    |               80%|            70%|           59%|       100%|
|Other                  |               31%|            73%|           96%|        90%|

![Precision and recall](figures/precision_recall.png)

## Where they disagree

The two classifiers gave different answers on 96 of 300 notes. The LLM was right on 62 of them, the keyword rules on 25, and both were wrong on 9.

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

**Where the LLM misses.** Grouped by the mistake, with one example note each.


|True                   |LLM said            | Errors|Example note                                              |
|:----------------------|:-------------------|------:|:---------------------------------------------------------|
|Blackberry removal     |Yard / outdoor work |     32|Cleared blackberries in the backyard, 2 loads to the dump |
|Junk removal & hauling |Yard / outdoor work |      7|Pickup load to recycling, yard debris                     |
|Other                  |Yard / outdoor work |      2|Hung holiday ligths, quoted on site                       |
|Junk removal & hauling |Other               |      1|Took two old appliances to the transfer station, Venmo    |
|Other                  |Pressure washing    |      1|Window washing, inside and out                            |

The big one is blackberry work filed as yard work: 32 of 75 blackberry jobs, and 21 of the 49 that use the plain picker wording. The system prompt defines Blackberry removal as its own category, and the model still folded it into the broader one. It also tends to read "yard debris" as yard work when the job was hauling it away. The keyword rules never misfile a note that contains "blackberr", because that rule is checked first.

The full disagreement list is in [`data/disagreements.csv`](data/disagreements.csv).



## Cost and latency


|                              | Keyword rules|                      LLM|
|:-----------------------------|-------------:|------------------------:|
|Cost per 1,000 notes          |            $0|                    $0.23|
|Median time per note          |          4 µs| 8.1 s (API alone: 1.3 s)|
|90th percentile time per note |              | 9.1 s (API alone: 1.9 s)|
|Tokens per call (in / out)    |           n/a|                1154 / 11|
|Runs offline                  |           Yes|                       No|

LLM cost is the per-call figure the CLI reports at API prices, summed over 300 calls. Input tokens include context the CLI adds on top of my prompt, so a direct API call with the same prompt would send fewer tokens and cost less. Wall-clock time is for one CLI call with 4 calls running at once, including process start; "API alone" is the time the CLI reports waiting on the model. Keyword time is the R port, averaged over 600,000 classifications.

## What I'd do with this

- **For jobs logged from the picker,** the rules are the right tool: close to perfect, free and instant. The LLM is worse on these notes, mostly because of the blackberry mistake.
- **For jobs typed by hand,** the rules misfile without any warning, and that skews the revenue-by-service and $/hour charts the app exists to produce. The cheapest fix is word boundaries (`\bmove\b`, `\bbeds?\b`), dropping place words from the rules, and a few synonyms.
- **An LLM isn't a drop-in upgrade.** It was better overall but wrong in a consistent direction on the business's main service line. That's the kind of error that moves a revenue-by-service chart, and it only showed up because the results were checked against labels.
- **The Hybrid** is what I'd ship: the rules handle what they're good at, and the LLM only sees the 23% of notes the rules can't place. It still can't fix a note the rules misfile with a keyword match.

## Limits

- The notes are synthetic, so the accuracy numbers describe how each classifier handles this kind of variation, not how often that variation shows up in real job logs.
- I wrote both the templates and the labels. The LLM was given the same category definitions I labeled with; the keyword rules were written earlier from real notes. The LLM has the easier job by design.
- One model, one prompt, one run. No prompt tuning.

## Reproduce

Needs R (dplyr, tidyr, purrr, readr, stringr, ggplot2, scales, jsonlite, withr, knitr), Node.js for the port check, and a logged-in Claude Code CLI for the LLM step.

```sh
Rscript R/01_make_data.R     # write data/jobs.csv
Rscript R/02_check_port.R    # R port vs the original JavaScript
Rscript R/03_run_llm.R       # LLM labels, cached in data/llm_predictions.csv
Rscript -e 'knitr::knit("README.Rmd")'
```

Step 3 is the only one that calls a model; the cached predictions are committed, so the README rebuilds without it.
