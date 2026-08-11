#!/usr/bin/env Rscript

# No stat159-specific R packages yet; base-r-image provides the R baseline.
packages <- c()

if (length(packages) > 0) {
  renv::install(packages)
}
