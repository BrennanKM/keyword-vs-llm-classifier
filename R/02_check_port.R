# Confirms the R port in R/keyword_classifier.R gives the same label as the
# original JavaScript function on every row. Needs Node.js on the PATH.
#
# Run from the repo root: Rscript R/02_check_port.R

suppressPackageStartupMessages({ library(dplyr); library(readr) })
source("R/keyword_classifier.R")

jobs <- read_csv("data/jobs.csv", show_col_types = FALSE)

js_labels <- system2("node", "js/classifyService.js", input = jobs$description, stdout = TRUE)
stopifnot(length(js_labels) == nrow(jobs))

check <- jobs |>
  transmute(id, description, js = js_labels, r = classify_keyword(description)) |>
  mutate(match = js == r)

write_csv(check, "data/keyword_port_check.csv")
message(sum(check$match), " of ", nrow(check), " rows match the JavaScript original.")
if (!all(check$match)) stop("Port mismatch, see data/keyword_port_check.csv")
