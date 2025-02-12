# remotes::install_github("nmfs-fish-tools/r4MAS")
# remotes::install_github("r4ss/r4ss")

library(r4MAS)
library(Rcpp)
library(jsonlite)
library(r4ss)

## Read SS input file
file_path <- "C:/Users/bai.li/Desktop/striped_marlin/"
data_file <- "MLS2019_data_v1.dat"
control_file <- "MLS2019_control_v2.ctl"
starter_file <- "starter.ss"
forecast_file <- "forecast.ss"
watage_file <- NULL
version <- "3.30"


# Read SS input data
ss_dat <- r4ss::SS_readdat(
  file = file.path(file_path, data_file),
  version = version,
  verbose = TRUE,
  echoall = FALSE,
  section = NULL
)
ss_ctl <- r4ss::SS_readctl(
  file = file.path(file_path, control_file),
  version = version,
  verbose = TRUE,
  echoall = lifecycle::deprecated(),
  use_datlist = TRUE,
  datlist = file.path(file_path, data_file),
)

ss_starter <- r4ss::SS_readstarter(
  file = file.path(file_path, starter_file),
  verbose = TRUE
)

ss_forecast <- r4ss::SS_readforecast(
  file = file.path(file_path, forecast_file),
  version = version,
  readAll = FALSE,
  verbose = TRUE,
  Nfleets = NULL,
  Nareas = NULL,
  nseas = NULL
)

ss_wtatage <- NULL

fleet_id <- unique(ss_dat$catch$fleet)
survey_id <- unique(ss_dat$CPUE$index)

## Convert SS inputs to MAS inputs


# Load r4MAS module
r4mas <- Rcpp::Module("rmas", PACKAGE="r4MAS")

# General settings
styr <- ss_dat$styr #1975
endyr <- ss_dat$endyr #2017
nyears <- ss_dat$endyr - ss_dat$styr + 1 #43

nseasons <- ss_dat$nseas #4

nages <- ss_dat$N_agebins #0

nlengths <- ss_dat$N_lbins #37 Use N_lbins or ss_dat$N_lbinspop?
# ss_dat$N_lbinspop #181

ngenders <- ss_dat$Nsexes #1

area <- vector(mode="list", length=ss_dat$N_areas) #1
for (i in 1:ss_dat$N_areas){
  area[[i]] <- new(r4mas$Area)
  area[[i]]$name <- paste("area", i, sep="")
}

# Recruitment settings
if (ss_ctl$SR_function == 3) {
  recruitment <- new(r4mas$BevertonHoltRecruitment)
}
if (ss_ctl$SR_function == 2) {
  recruitment <- new(r4mas$RickerRecruitment)
}

recruitment$R0$value <- exp(ss_ctl$SR_parm["SR_LN(R0)", "INIT"])
recruitment$R0$estimated <-
  ifelse (ss_ctl$SR_parm["SR_LN(R0)", "PHASE"]<0, FALSE, TRUE)
recruitment$R0$phase <- abs(ss_ctl$SR_parm["SR_LN(R0)", "PHASE"])
recruitment$R0$min <- exp(ss_ctl$SR_parm["SR_LN(R0)", "LO"])
recruitment$R0$max <- exp(ss_ctl$SR_parm["SR_LN(R0)", "HI"])

recruitment$h$value <- ss_ctl$SR_parm[2, "INIT"]
recruitment$h$estimated <-
  ifelse(ss_ctl$SR_parm[2, "PHASE"] < 0, FALSE, TRUE)
recruitment$h$phase <- abs(ss_ctl$SR_parm[2, "PHASE"])
recruitment$h$min <- ss_ctl$SR_parm[2, "LO"]
recruitment$h$max <- ss_ctl$SR_parm[2, "HI"]

recruitment$sigma_r$value <- ss_ctl$SR_parm["SR_sigmaR", "INIT"]
recruitment$sigma_r$estimated <-
  ifelse(ss_ctl$SR_parm["SR_sigmaR", "PHASE"] < 0, FALSE, TRUE)
recruitment$sigma_r$min <- ss_ctl$SR_parm["SR_sigmaR", "LO"]
recruitment$sigma_r$max <- ss_ctl$SR_parm["SR_sigmaR", "HI"]
recruitment$sigma_r$phase <- abs(ss_ctl$SR_parm["SR_sigmaR", "PHASE"])

recruitment$estimate_deviations <-
  ifelse(ss_ctl$recdev_phase < 0, FALSE, TRUE)
recruitment$constrained_deviations <- TRUE
recruitment$deviations_min <- -15.0
recruitment$deviations_max <- 15.0
recruitment$deviation_phase <- abs(ss_ctl$recdev_phase)
recruitment$SetDeviations(rep(0.1, times=nyears)) # SS main recr_dev: 1994 to 2015; SS uses bias correction ramp

# Growth settings
fleet_num <- length(fleet_id)
catch_waa <- vector(mode="list", length=fleet_num)

for (i in 1:fleet_num){

  catch_waa[[i]] <- vector(mode="list", length=ngenders)

  for (j in 1:ngenders){
    waa <-  as.vector(t(
      ss_wtatage[(ss_wtatage$Fleet==fleet_id[i] & ss_wtatage$Sex == j), age_id]
    ))

    if (ss_dat$CPUEinfo[ss_dat$CPUEinfo$Fleet==fleet_id[i], "Units"]==0) {
      catch_waa[[i]][[j]] <- rep(1.0, nages*nyears)
    } # Unit is number

    if (ss_dat$CPUEinfo[ss_dat$CPUEinfo$Fleet==fleet_id[i], "Units"]==1) {
      catch_waa[[i]][[j]] <- waa
    } # Unit is biomass
  }
}

print(ss_ctl$GrowthModel) #option 1: vonBert with L1&L2
show(r4mas$VonBertalanffyModified)
# growth <- new(r4mas$VonBertalanffyModified)
# growth$a_min$value <- min(om_input$ages)
# growth$a_max$value <- max(om_input$ages)
# growth$c$value <- 0.3
# growth$lmin$value <- 5
# growth$lmax$value <- 50
# growth$alpha_f$value <- om_input$a.lw
# growth$alpha_m$value <- om_input$a.lw
# growth$beta_f$value <- om_input$b.lw
# growth$beta_m$value <- om_input$b.lw

# Maturity settings
print(ss_ctl$maturity_option) #option 1: length logistic
# Current one sex, ignore fraction female input in the control file?

show(r4mas$Maturity)

# maturity <- vector(mode="list", length=ngenders)
# for (j in 1:ngenders){
#   maturity[[j]] <- new(r4mas$Maturity)
#   maturity[[j]]$values <- rep(1.0, nlengths)
# }

# Natural mortality settings
print(ss_ctl$natM_type) #option 3: agespecific (from age 0 to age 15)
natural_mortality <- vector(mode="list", length=ngenders)
if (ss_ctl$natM_type==0) {
  for (j in 1:ngenders){
    natural_mortality[[j]] <- new(r4mas$NaturalMortality) # No min and max settings
    if (j==1) {
      natural_mortality[[j]]$estimate <-
        ifelse(ss_ctl$MG_parms["NatM_p_1_Fem_GP_1", "PHASE"] < 0, FALSE, TRUE)
      natural_mortality[[j]]$phase <- abs(ss_ctl$MG_parms["NatM_p_1_Fem_GP_1", "PHASE"])
      natural_mortality[[j]]$values <- ss_ctl$MG_parms["NatM_p_1_Fem_GP_1", "INIT"]
    }

    if (j==2) {
      natural_mortality[[j]]$estimate <-
        ifelse(ss_ctl$MG_parms["NatM_p_1_Mal_GP_1", "PHASE"] < 0, FALSE, TRUE)
      natural_mortality[[j]]$phase <- abs(ss_ctl$MG_parms["NatM_p_1_Mal_GP_1", "PHASE"])
      natural_mortality[[j]]$values <- ss_ctl$MG_parms["NatM_p_1_Mal_GP_1", "INIT"]
    }
  }
}

if (ss_ctl$natM_type==3) {
  natural_mortality <- new(r4mas$NaturalMortality)
  natural_mortality$estimate <- FALSE # Not sure about it, not in the MG_parms
  natural_mortality$values <- ss_ctl$natM
}

# Movement settings
movement <- new(r4mas$Movement)
movement$connectivity_females <- c(0.0)
movement$connectivity_males <- c(0.0)
movement$connectivity_recruits <- c(0.0)

# Initial deviations
initial_deviations <- vector(mode="list", length=ngenders)

for (j in 1:ngenders){
  initial_deviations[[j]] <- new(r4mas$InitialDeviations)
  initial_deviations[[j]]$values <- rep(0.1, times=nages)
  initial_deviations[[j]]$estimate <- TRUE
  initial_deviations[[j]]$phase <- 2
}

# Create population
population=new(r4mas$Population)
for (y in 1:(nyears))
{
  population$AddMovement(movement$id, y)
}

population$AddNaturalMortality(natural_mortality$id, area1$id, "undifferentiated")
population$AddMaturity(maturity$id, area1$id, "undifferentiated")
population$AddRecruitment(recruitment$id, 1, area1$id)
population$SetInitialDeviations(initial_deviations$id, area1$id, "undifferentiated")
population$SetGrowth(growth$id)
population$sex_ratio <- 0.9999

# Catch index values and observation errors
# Catch unit: fleets 15-23 use biomass and the other fleets use number?
# How to handle 4 seasons of data?
catch_index <- vector(mode="list", length=fleet_num)
options(warn=1)
for (i in 1:fleet_num){
  print(i)
  catch_index[[i]] <- new(r4mas$IndexData)

  temp <- as.data.frame(cbind(styr:endyr, rep(-9999, nyears), rep(-9999, nyears)))
  colnames(temp) <- c("year", "catch", "catch_se")

  condition_rule <- ss_dat$catch$year[(ss_dat$catch$fleet==fleet_id[i] &
                                         ss_dat$catch$year>0)]
  temp$catch[temp$year %in% condition_rule] <- ss_dat$catch$catch[condition_rule]
  temp$catch_se[temp$year %in% condition_rule] <- ss_dat$catch$catch_se[condition_rule]

  catch_index[[i]]$values <- temp$catch
  catch_index[[i]]$error <- temp$catch_se

  catch_index[[i]]$missing_value <- -9999
}

# Catch composition data
# How to use length composition data in r4MAS?

# Likelihood component settings

# Fleet selectivity settings
# How to use size selectivity patterns in r4MAS?

# Fishing mortality settings
fishing_mortality <- new(r4mas$FishingMortality)
fishing_mortality$estimate <- TRUE
fishing_mortality$phase <- 1
fishing_mortality$min <- 0.0
fishing_mortality$max <- ss_ctl$maxF
fishing_mortality$SetValues(rep(0.01, nyears))

# Create the fleet


# Survey index values and observation errors

# Survey composition

# Likelihood component settings

# Survey selectivity settings

# Create the survey

## Build the MAS model

## Run `MAS`, save `MAS` outputs, and reset `MAS`

# # Run MAS
# mas_model$Run()
#
# # Write MAS outputs to a json file
# write(mas_model$GetOutput(),
#       file=file.path(data_dir, "mas_output.json"))
#
# # Reset MAS for next run
# mas_model$Reset()
#
# # Import MAS output
# mas_output <- jsonlite::read_json(file.path(data_dir, "mas_output.json"))

