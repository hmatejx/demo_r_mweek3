# load required libraries
library(tidyverse)
library(data.table)
library(ggplot2)
library(splitstackshape)
library(readxl)
library(fst)
library(lubridate)


# load DB
mort <- as_tibble(read_fst("demo_r_mweek3_pjangrp3.fst"))
mort.pivoted <- as_tibble(read_fst("demo_r_mweek3_pjangrp3-pivoted.fst"))


# plot an example
mort.pivoted %>%
  filter(geo %in% c("ITC49", "ITC4A", "ITC46", "ITH34", "ITH35", "ITH43"),
         sex == "T", date > "2020-01-01", date < "2021-01-01") %>%
  ggplot(aes(x = date, y = `ASMR`, color = geo)) +
  geom_line(size = 1) +
  theme_bw()
