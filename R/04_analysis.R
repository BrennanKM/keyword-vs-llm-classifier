# Scores both classifiers against the true labels and builds every table and
# chart the README uses. Sourced by README.Rmd; can also be run on its own.

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(readr)
  library(stringr); library(ggplot2); library(scales)
})
source("R/keyword_classifier.R")

LABELS <- c("Blackberry removal", "Pressure washing", "Junk removal & hauling",
            "Yard / outdoor work", "Other")
COLORS <- c("Keyword rules" = "#2a78d6", "LLM" = "#eb6834", "Hybrid" = "#1baf7a")

jobs <- read_csv("data/jobs.csv", show_col_types = FALSE)
llm  <- read_csv("data/llm_predictions.csv", show_col_types = FALSE)

# Map the LLM's reply onto a label. Exact name first, then a case-insensitive match.
normalize_label <- function(x) {
  x <- str_squish(str_remove_all(x, "[\"'*.`]"))
  hit <- match(tolower(x), tolower(LABELS))
  ifelse(is.na(hit), "Unparsed", LABELS[hit])
}

# Which keyword fired, for explaining the rules' mistakes.
RULES <- list(
  "Blackberry removal"     = "blackberr",
  "Pressure washing"       = c("pressure", "driveway", "patio", "deck", "sidewalk", "walkway", "wash"),
  "Junk removal & hauling" = c("junk", "haul", "dump", "move", "pavers", "furniture", "bed"),
  "Yard / outdoor work"    = c("yard", "bark", "weed", "chop", "wood", "seaside", "outdoor", "stain", "post", "fig")
)
fired_keyword <- function(text, label) {
  if (label == "Other") return("(nothing matched)")
  terms <- RULES[[label]]
  terms[str_detect(tolower(text), fixed(terms))][1]
}

d <- jobs |>
  inner_join(select(llm, id, llm_raw), by = "id") |>
  mutate(
    keyword = classify_keyword(description),
    llm     = normalize_label(llm_raw),
    hybrid  = if_else(keyword == "Other", llm, keyword)
  )

long <- d |>
  select(id, description, true_label, style, `Keyword rules` = keyword, LLM = llm, Hybrid = hybrid) |>
  pivot_longer(c(`Keyword rules`, LLM, Hybrid), names_to = "classifier", values_to = "pred") |>
  mutate(classifier = factor(classifier, levels = names(COLORS)),
         correct = pred == true_label)

# ---- Overall scores ---------------------------------------------------------
per_class <- long |>
  group_by(classifier) |>
  group_modify(function(g, ...) {
    map_dfr(LABELS, function(lab) {
      tp <- sum(g$pred == lab & g$true_label == lab)
      tibble(class = lab,
             support   = sum(g$true_label == lab),
             predicted = sum(g$pred == lab),
             precision = if (sum(g$pred == lab) > 0) tp / sum(g$pred == lab) else NA_real_,
             recall    = tp / sum(g$true_label == lab))
    })
  }) |>
  ungroup() |>
  mutate(f1 = if_else(precision + recall > 0, 2 * precision * recall / (precision + recall), 0),
         class = factor(class, levels = LABELS))

overall <- long |>
  group_by(classifier) |>
  summarise(accuracy = mean(correct),
            canonical = mean(correct[style == "canonical"]),
            variant   = mean(correct[style == "variant"]),
            .groups = "drop") |>
  left_join(per_class |> group_by(classifier) |> summarise(macro_f1 = mean(f1, na.rm = TRUE)),
            by = "classifier")

# ---- Disagreements ----------------------------------------------------------
disagree <- d |>
  filter(keyword != llm) |>
  mutate(winner = case_when(
    keyword == true_label ~ "Keyword rules right",
    llm == true_label     ~ "LLM right",
    TRUE                  ~ "Both wrong"))

disagree_tally <- count(disagree, winner)

keyword_errors <- d |>
  filter(keyword != true_label) |>
  mutate(fired = map2_chr(description, keyword, fired_keyword)) |>
  count(fired, keyword, sort = TRUE, name = "errors")

keyword_error_examples <- d |>
  filter(keyword != true_label) |>
  mutate(fired = map2_chr(description, keyword, fired_keyword)) |>
  group_by(fired) |>
  slice_head(n = 1) |>
  ungroup() |>
  left_join(select(keyword_errors, fired, errors), by = "fired") |>
  arrange(desc(errors)) |>
  select(description, true_label, keyword, fired, errors)

llm_errors <- d |>
  filter(llm != true_label) |>
  select(id, description, true_label, llm, llm_raw)

# ---- Cost and latency -------------------------------------------------------
reps <- 2000
t_kw <- system.time(for (i in seq_len(reps)) classify_keyword(d$description))[["elapsed"]]
kw_us_per_row <- t_kw / (reps * nrow(d)) * 1e6

llm_cost <- llm |>
  summarise(calls        = n(),
            in_tok_mean  = mean(input_tokens),
            out_tok_mean = mean(output_tokens),
            cost_total   = sum(cost_usd),
            cost_per_1k  = mean(cost_usd) * 1000,
            api_median   = median(api_ms),
            api_p90      = quantile(api_ms, .9),
            wall_median  = median(wall_ms),
            wall_p90     = quantile(wall_ms, .9))

hybrid_llm_share <- mean(d$keyword == "Other")

# ---- Charts -----------------------------------------------------------------
theme_viz <- theme_minimal(base_size = 12) +
  theme(plot.background = element_rect(fill = "#fcfcfb", color = NA),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(color = "#e4e3df", linewidth = .3),
        axis.text = element_text(color = "#52514e"),
        plot.title = element_text(face = "bold", color = "#0b0b0b"),
        plot.subtitle = element_text(color = "#52514e"),
        legend.position = "top", legend.justification = "left",
        strip.text = element_text(face = "bold", hjust = 0))

short <- c("Blackberry removal" = "Blackberry", "Pressure washing" = "Pressure wash",
           "Junk removal & hauling" = "Junk & hauling", "Yard / outdoor work" = "Yard / outdoor",
           "Other" = "Other", "Unparsed" = "Unparsed")

conf <- long |>
  filter(classifier != "Hybrid") |>
  mutate(classifier = droplevels(classifier)) |>
  count(classifier, true_label, pred) |>
  complete(classifier, true_label = LABELS, pred = LABELS, fill = list(n = 0)) |>
  group_by(classifier, true_label) |>
  mutate(share = n / pmax(sum(n), 1)) |>
  ungroup() |>
  mutate(true_label = factor(short[true_label], levels = rev(short[LABELS])),
         pred = factor(short[pred], levels = short[c(LABELS, "Unparsed")]))

fig_confusion <- ggplot(conf, aes(pred, true_label, fill = share)) +
  geom_tile(color = "#fcfcfb", linewidth = 1) +
  geom_text(aes(label = if_else(n > 0, as.character(n), ""),
                color = share > .55), size = 3.6) +
  scale_fill_gradient(low = "#f1f0ec", high = "#2a78d6", limits = c(0, 1), guide = "none") +
  scale_color_manual(values = c(`TRUE` = "#ffffff", `FALSE` = "#0b0b0b"), guide = "none") +
  facet_wrap(~classifier) +
  labs(title = "Confusion matrices",
       subtitle = "Rows are the true category; cells count jobs; shading is the share of each row",
       x = "Predicted", y = "True") +
  theme_viz +
  theme(axis.text.x = element_text(angle = 30, hjust = 1), panel.grid = element_blank())

pr_long <- per_class |>
  filter(classifier != "Hybrid") |>
  pivot_longer(c(precision, recall), names_to = "metric") |>
  mutate(metric = str_to_title(metric), class = factor(short[as.character(class)], levels = rev(short[LABELS])))

fig_pr <- ggplot(pr_long, aes(value, class, color = classifier)) +
  geom_line(aes(group = class), color = "#c9c8c2", linewidth = .6) +
  geom_point(size = 3.2) +
  scale_x_continuous(labels = percent, limits = c(0, 1)) +
  scale_color_manual(values = COLORS[1:2], name = NULL) +
  facet_wrap(~metric) +
  labs(title = "Precision and recall by category", x = NULL, y = NULL) +
  theme_viz

style_acc <- overall |>
  select(classifier, Canonical = canonical, Variant = variant) |>
  pivot_longer(-classifier, names_to = "style", values_to = "accuracy")

fig_style <- ggplot(style_acc, aes(style, accuracy, fill = classifier)) +
  geom_col(position = position_dodge(width = .8), width = .7) +
  geom_text(aes(label = percent(floor(accuracy * 100) / 100, accuracy = 1)),
            position = position_dodge(width = .8), vjust = -.5, size = 3.4, color = "#0b0b0b") +
  scale_y_continuous(labels = percent, limits = c(0, 1.08), breaks = seq(0, 1, .25)) +
  scale_fill_manual(values = COLORS, name = NULL) +
  labs(title = "Accuracy on canonical vs variant wording",
       subtitle = "Hybrid = keyword rules first, LLM only when the rules return Other",
       x = NULL, y = "Accuracy") +
  theme_viz

save_fig <- function(p, file, w = 9, h = 4.8) ggsave(file, p, width = w, height = h, dpi = 150, bg = "#fcfcfb")
save_fig(fig_confusion, "figures/confusion.png", h = 5.2)
save_fig(fig_pr, "figures/precision_recall.png")
save_fig(fig_style, "figures/accuracy_by_style.png", w = 8, h = 4.6)
