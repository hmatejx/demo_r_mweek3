# clean-up
rm(list = ls())


# load required libraries
library(tidyverse)
library(data.table)
library(ggplot2)
library(splitstackshape)
library(readxl)
library(fst)
library(lubridate)


# interesting link for bulk download of EC data
# https://ec.europa.eu/eurostat/estat-navtree-portlet-prod/BulkDownloadListing?dir=data&sort=1&sort=2

# The NUTS area information can be downloaded here:
# https://ec.europa.eu/eurostat/documents/345175/629341/NUTS2021.xlsx
# NUTS area maps, e.g. for Italy, can be found in such links (just change the country code)
# https://ec.europa.eu/eurostat/documents/345175/7451602/nuts-map-IT.pdf

# The mortality and population size data can be downloaded here
# https://ec.europa.eu/eurostat/estat-navtree-portlet-prod/BulkDownloadListing?sort=1&file=data%2Fdemo_r_mweek3.tsv.gz
# https://ec.europa.eu/eurostat/estat-navtree-portlet-prod/BulkDownloadListing?sort=1&file=data%2Fdemo_r_pjangrp3.tsv.gz
# unzip these and put them in the same location as the script

# Limitations of the current version
# 1. Population counts only go back to 2014, whereas the mortality data goes back to 2000 for some regions
# 2. The 2022 population is linearly extrapolated the 2022 based on the 2020-2021 slope
# 3. During the year the population is linearly interpolated to get the population for a certain week
# 4. There are some deaths attributed to week 99 which is included but ignored in the ASMR calculations
# 5. Handling of dates... the data comes in year-week format, I did a quick & dirty "2021W11" -> "2021-01-01" + 11*7


# load raw data
mort <- fread("demo_r_mweek3.tsv", sep = "\t", header = T, stringsAsFactors = F)
pop <- fread("demo_r_pjangrp3.tsv", sep = "\t", header = T, stringsAsFactors = F)
regions <- read_xlsx("NUTS2021.xlsx", sheet = "NUTS & SR 2021", range = "A1:H2125")


# split the first column (comma separated)
# mortality
cSplit(mort, "unit,sex,age,geo\\time", sep = ",", drop = T, type.convert = F) %>%
  as_tibble() -> mort
names(mort)[(ncol(mort) - 3):ncol(mort)] <- c("unit", "sex", "age", "geo")
# population
cSplit(pop, "sex,unit,age,geo\\time", sep = ",", drop = T, type.convert = F) %>%
  as_tibble() -> pop
names(pop)[(ncol(pop) - 3):ncol(pop)] <- c("sex", "unit", "age", "geo")


# pivot longer
# mortality
mort %>%
  pivot_longer(`2022W26`:`2000W01`) %>%
  select(-unit) -> mort
# population
pop %>% 
  pivot_longer(`2014`:`2021`, names_to = "year", values_to = "population") %>%
  select(-unit) -> pop


# convert values to numeric
# mortality
mort %>%
  mutate(value = as.numeric(trimws(value, whitespace = "[ p]"))) -> mort
# population
pop %>%
  mutate(population = as.numeric(trimws(population, whitespace = "[ bep]"))) -> pop


# convert year-week to date by taking the first day of the year and adding the weeks
# I am sure there is a better/more accurate way to do this...)
mort %>%
  mutate(year = substr(name, 1, 4),
         week = substr(name, 6, 7),
         beginning = ymd(str_c(year, "-01-01")),
         date = beginning + weeks(week)) %>%
  select(-name, -beginning) -> mort
  

# add in NUTS region information (name)
mort %>%
  left_join(regions %>% 
              rename(geo = `Code 2021`) %>%
              select(geo:`NUTS level`),
            by = "geo") -> mort


# extrapolate the 2022 population
pop %>% filter(year == "2020") %>% 
  left_join(pop %>% filter(year == "2021"), 
            by = c("geo", "age", "sex"),
            suffix = c(".2020", ".2021")) %>%
  mutate(population = population.2021 + population.2021 - population.2020,
         year = "2022") %>%
  select(geo:sex, year, population) %>%
  bind_rows(pop) %>%
  arrange(geo, age, sex, year) -> pop


# extrapolate the population weekly
mort %>% 
  filter(geo == "AL", sex == "F", age == "TOTAL", week != "99") %>% 
  select(year, week) %>%
  group_by(year) %>%
  mutate(maxweek = max(week)) -> yearweeks
pop %>% 
  mutate(yearn = as.character(as.numeric(year) + 1)) -> pop.1
pop %>%
  rename(yearn = year) %>%
  left_join(pop.1, by = c("geo", "age", "sex", "yearn")) %>%
  select(-year) %>%
  rename(year = yearn) -> pop.2
pop.2 %>%
  left_join(yearweeks, by = "year") -> pop.3
pop.3 %>%
  mutate(
    w = as.numeric(week),
    mw = as.numeric(maxweek),
    population = (population.y * (mw - w) + population.x * (w - 1)) / (mw - 1)) %>%
  select(-w, -mw) -> pop.4
pop.4 %>%
  mutate(population = if_else(is.na(population), population.x, population)) %>%
  select(geo, age, sex, year, week, population) -> pop.interpolated


# add in population information
mort %>%
  left_join(pop.interpolated, by = c("geo", "age", "sex", "year", "week")) -> mort
rm(pop.1, pop.2, pop.3, pop.4)


# calculate mortality rate per 100k population site
mort %>%
  mutate(rate = value / population * 1e5) -> mort


# calculate ASMR using the revised ESP2013 population
mort %>%
  group_by(geo, year, week, sex) %>%
  summarize(date = first(date),
            ASMR = rate[age == "Y_LT5"]   * 5000/1e5 +
                   rate[age == "Y5-9"]    * 5500/1e5 +
                   rate[age == "Y10-14"]  * 5500/1e5 +
                   rate[age == "Y15-19"]  * 5500/1e5 +
                   rate[age == "Y20-24"]  * 6000/1e5 +
                   rate[age == "Y25-29"]  * 6000/1e5 +
                   rate[age == "Y30-34"]  * 6500/1e5 +
                   rate[age == "Y35-39"]  * 7000/1e5 +
                   rate[age == "Y40-44"]  * 7000/1e5 +
                   rate[age == "Y45-49"]  * 7000/1e5 +
                   rate[age == "Y50-54"]  * 7000/1e5 +
                   rate[age == "Y55-59"]  * 6500/1e5 +
                   rate[age == "Y60-64"]  * 6000/1e5 +
                   rate[age == "Y65-69"]  * 5500/1e5 +
                   rate[age == "Y70-74"]  * 5000/1e5 +
                   rate[age == "Y75-79"]  * 4000/1e5 +
                   rate[age == "Y80-84"]  * 2500/1e5 +
                   rate[age == "Y85-89"]  * 1500/1e5 + 
                   rate[age == "Y_GE90"]  * 1000/1e5,
            ASMR065 = rate[age == "Y_LT5"]   * 5000/1e5 +
                      rate[age == "Y5-9"]    * 5500/1e5 +
                      rate[age == "Y10-14"]  * 5500/1e5 +
                      rate[age == "Y15-19"]  * 5500/1e5 +
                      rate[age == "Y20-24"]  * 6000/1e5 +
                      rate[age == "Y25-29"]  * 6000/1e5 +
                      rate[age == "Y30-34"]  * 6500/1e5 +
                      rate[age == "Y35-39"]  * 7000/1e5 +
                      rate[age == "Y40-44"]  * 7000/1e5 +
                      rate[age == "Y45-49"]  * 7000/1e5 +
                      rate[age == "Y50-54"]  * 7000/1e5 +
                      rate[age == "Y55-59"]  * 6500/1e5 +
                      rate[age == "Y60-64"]  * 6000/1e5,
            `ASMR65+` = rate[age == "Y65-69"]  * 5500/1e5 +
                        rate[age == "Y70-74"]  * 5000/1e5 +
                        rate[age == "Y75-79"]  * 4000/1e5 +
                        rate[age == "Y80-84"]  * 2500/1e5 +
                        rate[age == "Y85-89"]  * 1500/1e5 + 
                        rate[age == "Y_GE90"]  * 1000/1e5) %>%
  ungroup() -> mort.ASMR


# add ASMR, ASMR 0 to 65, and ASMR 65+ to the dataset
mort %>%
  bind_rows(
    mort %>% 
      filter(age == "TOTAL") %>%
      left_join(mort.ASMR %>% select(-date), by = c("sex", "geo", "year", "week")) %>%
      pivot_longer(ASMR:`ASMR65+`, names_to = "age.1", values_to = "values.1") %>%
      mutate(age = age.1, rate = values.1) %>%
      select(-age.1, -values.1)
  ) -> mort
rm(mort.ASMR)


# sanity plot
mort %>%
  filter(geo %in% c("ITC46", "ITC47", "ITH34", "ITH35", "ITH43"),
         sex == "T", age == "ASMR",  date > "2014-01-01") %>%
  ggplot(aes(x = date, y = rate, color = geo)) +
  geom_line(size = 1) +
  theme_bw()


# save data frame as FST format
write_fst(mort, "demo_r_mweek3_pjangrp3.fst", compress = 99)
# save as TSV as well
fwrite(mort, "demo_r_mweek3_pjangrp3.tsv", sep = "\t", quote = F, dec = ".", row.names = F)
# mort <- as_tibble(read_fst("mort.fst"))


# clean-up memory
gc()
