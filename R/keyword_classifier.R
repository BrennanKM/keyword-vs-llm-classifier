# R port of classifyService() from the Stats view of the field-service app
# (BrennanKM/field-service-client-directory, index.html). Same regexes, same
# order: the first rule that matches wins. R/check_port.R confirms this port
# returns the same label as the original JavaScript on every row.

classify_keyword <- function(s) {
  t <- tolower(ifelse(is.na(s), "", s))
  dplyr::case_when(
    grepl("blackberr", t)                                                   ~ "Blackberry removal",
    grepl("pressure|driveway|patio|deck|sidewalk|walkway|wash", t)          ~ "Pressure washing",
    grepl("junk|haul|dump|move|pavers|furniture|bed", t)                    ~ "Junk removal & hauling",
    grepl("yard|bark|weed|chop|wood|seaside|outdoor|stain|post|fig", t)     ~ "Yard / outdoor work",
    TRUE                                                                    ~ "Other"
  )
}
