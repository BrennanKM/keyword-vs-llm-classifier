# Builds the synthetic job-description set used in the comparison.
#
# Every row is generated. No real client, address, phone number or job record
# is used. Each row gets a true category at the moment it's written, using the
# labeling rule in LABELING.md: the category is the main service the job was
# billed for.
#
# Templates are tagged "canonical" (how the app's own service picker writes
# them, e.g. "Pressure washing driveway") or "variant" (shorthand, synonyms,
# typos and combined jobs, the way notes get typed on a phone after a job).
#
# Run from the repo root: Rscript R/01_make_data.R

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

set.seed(20261117)
N <- 300

fill <- function(pattern, slots) {
  str_replace_all(pattern, "\\{(\\w+)\\}", function(m) {
    vapply(str_sub(m, 2, -2), function(key) sample(slots[[key]], 1), character(1))
  })
}

slots <- list(
  place   = c("along the back fence", "behind the shed", "on the hillside", "by the creek",
              "in the side yard", "near the garden", "on the slope", "in the backyard",
              "along the property line", "by the driveway", "under the deck", "around the pond"),
  surface = c("driveway", "back patio", "deck", "sidewalk", "front walkway", "siding",
              "roof", "fence", "garage floor", "pavers", "stone steps", "patio and walkway"),
  stuff   = c("old furniture", "a mattress and bed frame", "yard debris", "construction scraps",
              "an old hot tub", "broken pavers", "two old appliances", "boxes from the garage",
              "scrap wood", "a busted treadmill", "carpet and pad", "a couch"),
  n       = c("2", "3", "4", "5", "6"),
  task    = c("weeding", "spreading bark", "raking", "hedge trimming", "mowing", "general cleanup")
)

# label, style, weight, pattern
templates <- tribble(
  ~label,                    ~style,      ~w, ~pattern,
  # Blackberry removal
  "Blackberry removal",      "canonical", 6,  "Blackberry removal {place}",
  "Blackberry removal",      "canonical", 3,  "Cleared blackberries {place}, {n} loads to the dump",
  "Blackberry removal",      "canonical", 2,  "Himalayan blackberry clearing {place}",
  "Blackberry removal",      "variant",   2,  "Pulled berry vines {place}",
  "Blackberry removal",      "variant",   2,  "Bramble clearing {place}",
  "Blackberry removal",      "variant",   1,  "Cut back black berries {place}",
  "Blackberry removal",      "variant",   1,  "BB removal {place}",
  "Blackberry removal",      "variant",   1,  "Invasive berry removal {place}, dug out root balls",
  "Blackberry removal",      "variant",   1,  "Cleared thorny vines {place}",
  "Blackberry removal",      "variant",   1,  "Dug out blackberry roots {place}, hauled the brush",
  # Pressure washing
  "Pressure washing",        "canonical", 6,  "Pressure washing {surface}",
  "Pressure washing",        "canonical", 3,  "Power washed the {surface}",
  "Pressure washing",        "canonical", 1,  "Pressure wash and seal {surface}",
  "Pressure washing",        "variant",   2,  "PW {surface}",
  "Pressure washing",        "variant",   2,  "Cleaned moss off the {surface}",
  "Pressure washing",        "variant",   1,  "Soft wash on the roof, moss treatment",
  "Pressure washing",        "variant",   1,  "Surface cleaner on the {surface}",
  "Pressure washing",        "variant",   1,  "Blasted algae off the {surface}",
  "Pressure washing",        "variant",   1,  "Presure washing {surface}",
  # Junk removal & hauling
  "Junk removal & hauling",  "canonical", 5,  "Junk removal, {stuff}",
  "Junk removal & hauling",  "canonical", 3,  "Hauled {stuff} to the dump",
  "Junk removal & hauling",  "canonical", 3,  "Dump run, {stuff}",
  "Junk removal & hauling",  "variant",   2,  "Garage cleanout, {n} truck loads",
  "Junk removal & hauling",  "variant",   2,  "Took {stuff} to the transfer station",
  "Junk removal & hauling",  "variant",   1,  "Removed {stuff} from the basement",
  "Junk removal & hauling",  "variant",   1,  "Estate cleanout, {n} loads",
  "Junk removal & hauling",  "variant",   1,  "Appliance pickup, old fridge and washer",
  "Junk removal & hauling",  "variant",   1,  "Pickup load to recycling, {stuff}",
  # Yard / outdoor work
  "Yard / outdoor work",     "canonical", 5,  "Yard work, {task}",
  "Yard / outdoor work",     "canonical", 2,  "Weeding {place}",
  "Yard / outdoor work",     "canonical", 2,  "Spread {n} yards of bark",
  "Yard / outdoor work",     "canonical", 2,  "Chopped and stacked firewood",
  "Yard / outdoor work",     "canonical", 1,  "Stained the fence",
  "Yard / outdoor work",     "variant",   2,  "Mulched the flower beds",
  "Yard / outdoor work",     "variant",   1,  "Trimmed hedges and raked leaves",
  "Yard / outdoor work",     "variant",   1,  "Mowed and edged the lawn",
  "Yard / outdoor work",     "variant",   1,  "Removed ivy from the fence",
  "Yard / outdoor work",     "variant",   1,  "Deck staining, two coats",
  "Yard / outdoor work",     "variant",   1,  "Planted shrubs in the front beds",
  "Yard / outdoor work",     "variant",   1,  "Weed whacking along the driveway",
  "Yard / outdoor work",     "variant",   1,  "Stump grinding, 2 stumps",
  "Yard / outdoor work",     "variant",   1,  "Dug a drainage trench {place}",
  # Other
  "Other",                   "canonical", 2,  "Quote visit, no work done",
  "Other",                   "canonical", 1,  "Fixed a gate latch",
  "Other",                   "canonical", 1,  "Hung holiday lights",
  "Other",                   "variant",   1,  "Window washing, inside and out",
  "Other",                   "variant",   1,  "Assembled patio furniture",
  "Other",                   "variant",   1,  "Painted the guest bedroom",
  "Other",                   "variant",   1,  "Mounted a TV in the living room",
  "Other",                   "variant",   1,  "Installed a window AC unit"
)

# Target mix, close to the business's own job mix.
class_share <- c("Blackberry removal" = .25, "Pressure washing" = .25,
                 "Junk removal & hauling" = .20, "Yard / outdoor work" = .20, "Other" = .10)
class_n <- round(class_share * N)

typo <- function(x) {
  words <- str_split(x, " ")[[1]]
  long <- which(nchar(words) >= 5)
  if (length(long) == 0) return(x)
  i <- if (length(long) == 1) long else sample(long, 1)
  w <- words[i]
  j <- sample(2:(nchar(w) - 1), 1)
  words[i] <- if (runif(1) < .5) {
    paste0(str_sub(w, 1, j - 1), str_sub(w, j + 1))                       # drop a letter
  } else {
    paste0(str_sub(w, 1, j - 1), str_sub(w, j + 1, j + 1), str_sub(w, j, j), str_sub(w, j + 2))  # swap two
  }
  paste(words, collapse = " ")
}

tails <- c(", 3 hrs", ", paid cash", ", repeat client", ", 2 guys", ", quoted on site", ", Venmo")

jobs <- imap_dfr(class_n, function(n, lab) {
  t <- filter(templates, label == lab)
  idx <- sample(seq_len(nrow(t)), n, replace = TRUE, prob = t$w)
  tibble(true_label = lab, style = t$style[idx], template = t$pattern[idx]) |>
    mutate(description = map_chr(template, fill, slots = slots))
}) |>
  mutate(
    has_typo    = runif(n()) < .08,
    description = if_else(has_typo, map_chr(description, typo), description),
    style       = if_else(has_typo, "variant", style),
    description = if_else(runif(n()) < .20, paste0(description, sample(tails, n(), TRUE)), description),
    description = if_else(runif(n()) < .25, str_to_lower(description), description)
  ) |>
  slice_sample(prop = 1) |>
  mutate(id = sprintf("J%03d", row_number())) |>
  select(id, description, true_label, style, has_typo)

write_csv(jobs, "data/jobs.csv")
message("Wrote ", nrow(jobs), " rows to data/jobs.csv")
print(count(jobs, true_label, style))
