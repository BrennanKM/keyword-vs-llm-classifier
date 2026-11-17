# Classifies every job description with an LLM, one call per row, and records
# the label, tokens, reported cost and latency. Results are cached in
# data/llm_predictions.csv so the README can be rebuilt without new calls.
# Rows already in the cache are skipped, so a stopped run picks up where it left off.
#
# Calls go through the Claude Code CLI in print mode (`claude -p`) with a
# replacement system prompt and no tools, so each call is a single model turn.
# Needs a logged-in `claude` on the PATH, or set CLAUDE_BIN to its full path.
# No API key is read or stored by this script.
#
# Run from the repo root: Rscript R/03_run_llm.R

suppressPackageStartupMessages({
  library(dplyr); library(purrr); library(readr); library(jsonlite); library(parallel)
})

MODEL   <- Sys.getenv("LLM_MODEL", "claude-haiku-5-5")
BIN     <- Sys.getenv("CLAUDE_BIN", "claude")
WORKERS <- as.integer(Sys.getenv("LLM_WORKERS", "4"))
OUT     <- "data/llm_predictions.csv"

LABELS <- c("Blackberry removal", "Pressure washing", "Junk removal & hauling",
            "Yard / outdoor work", "Other")

SYSTEM_PROMPT <- paste(
  "You sort job notes from a small outdoor-services business into one service category.",
  "Pick the main service the job was billed for.",
  "Categories:",
  "Blackberry removal: clearing blackberry or other bramble and invasive berry vines.",
  "Pressure washing: pressure, power or soft washing of hard surfaces, roofs, siding or fences, including moss and algae cleaning.",
  "Junk removal & hauling: hauling away junk, debris, furniture or appliances, dump runs and cleanouts.",
  "Yard / outdoor work: weeding, mulch and bark, mowing, pruning, planting, staining, firewood, stumps, digging and other yard upkeep.",
  "Other: anything else, including indoor work, small repairs and visits with no work done.",
  "Reply with the category name exactly as written above and nothing else.",
  sep = "\n"
)

jobs <- read_csv("data/jobs.csv", show_col_types = FALSE)
done <- if (file.exists(OUT)) read_csv(OUT, show_col_types = FALSE) else NULL
todo <- if (is.null(done)) jobs else filter(jobs, !id %in% done$id)
message(nrow(todo), " rows to classify with ", MODEL, " using ", WORKERS, " workers")

work_dir <- tempfile("llm-run-")
dir.create(work_dir)

classify_one <- function(id, description) {
  args <- c("-p", shQuote(paste0("Job note: ", description)),
            "--system-prompt", shQuote(SYSTEM_PROMPT),
            "--model", MODEL,
            "--tools", shQuote(""),
            "--output-format", "json",
            "--no-session-persistence",
            "--strict-mcp-config",
            "--setting-sources", shQuote(""))
  t0  <- Sys.time()
  out <- withr::with_dir(work_dir, suppressWarnings(system2(BIN, args, stdout = TRUE, stderr = FALSE)))
  wall_ms <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000
  res <- tryCatch(fromJSON(paste(out, collapse = "\n")), error = function(e) NULL)
  if (is.null(res) || isTRUE(res$is_error)) {
    return(tibble(id = id, llm_raw = paste(out, collapse = " "), error = TRUE))
  }
  u <- res$usage
  tibble(
    id            = id,
    llm_raw       = trimws(res$result),
    error         = FALSE,
    model         = MODEL,
    input_tokens  = u$input_tokens + u$cache_creation_input_tokens + u$cache_read_input_tokens,
    output_tokens = u$output_tokens,
    cost_usd      = res$total_cost_usd,
    api_ms        = res$duration_api_ms,
    wall_ms       = wall_ms
  )
}

if (nrow(todo) > 0) {
  chunks <- split(todo, ceiling(seq_len(nrow(todo)) / 20))
  for (ch in chunks) {
    rows <- mcmapply(classify_one, ch$id, ch$description,
                     SIMPLIFY = FALSE, mc.cores = WORKERS)
    new  <- bind_rows(rows)
    errs <- filter(new, error)
    if (nrow(errs) > 0) {
      message("Errors on ", nrow(errs), " rows, first: ", substr(errs$llm_raw[1], 1, 300))
      new <- filter(new, !error)
    }
    new <- select(new, -error)
    write_csv(new, OUT, append = file.exists(OUT))
    message("Saved ", nrow(new), " rows; total ", nrow(read_csv(OUT, show_col_types = FALSE)))
    if (nrow(errs) == nrow(ch)) stop("Every call in the batch failed. Is `claude` logged in?")
  }
}

preds <- read_csv(OUT, show_col_types = FALSE)
off_list <- filter(preds, !llm_raw %in% LABELS)
message(nrow(preds), " rows cached. ", nrow(off_list), " replies were not an exact category name.")
