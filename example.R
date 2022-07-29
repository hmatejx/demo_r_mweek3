# load required libraries
library(tidyverse)
library(data.table)
library(ggplot2)
library(splitstackshape)
library(readxl)
library(fst)
library(lubridate)


mort <- as_tibble(read_fst("demo_r_mweek3_pjangrp3.fst"))


mort %>%
  filter(geo %in% c("ITC49", "ITC4A", "ITC46", "ITH34", "ITH35", "ITH43"),
         sex == "T", age == "ASMR",  date > "2020-01-01", date < "2021-01-01") %>%
  ggplot(aes(x = date, y = rate, color = geo)) +
  geom_line(size = 1) +
  theme_bw()
