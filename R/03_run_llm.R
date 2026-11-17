# Classifies every job description with an LLM, one call per row, and records
# the label, tokens, reported cost and latency. Results are cached in
# data/llm_predictions.csv so the README can be rebuilt without new calls.
# Rows already in the cache are skipped, so a stopped run picks up where it left off.
#
# PROMPT_VERSION picks the system prompt: v1 (category definitions only) or
# v2 (v1 plus rules for close calls and six examples, written after reading
# v1's mistakes). v1 results go to data/llm_predictions.csv, v2 to
# data/llm_predictions_v2.csv.
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
PROMPT  <- Sys.getenv("PROMPT_VERSION", "v1")   # prompts/v1.txt or prompts/v2.txt
OUT     <- if (PROMPT == "v1") "data/llm_predictions.csv" else paste0("data/llm_predictions_", PROMPT, ".csv")

LABELS <- c("Blackberry removal", "Pressure washing", "Junk removal & hauling",
            "Yard / outdoor work", "Other")

SYSTEM_PROMPT <- paste(readLines(file.path("prompts", paste0(PROMPT, ".txt"))), collapse = "\n")

jobs <- read_csv("data/jobs.csv", show_col_types = FALSE)
done <- if (file.exists(OUT)) read_csv(OUT, show_col_types = FALSE) else NULL
todo <- if (is.null(done)) jobs else filter(jobs, !id %in% done$id)
message(nrow(todo), " rows to classify with ", MODEL, ", prompt ", PROMPT, " using ", WORKERS, " workers")

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
    prompt        = PROMPT,
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
