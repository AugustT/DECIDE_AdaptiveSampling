
### looking at metrics for all moths
# library(terra)
library(raster)
library(dismo)
library(foreach)
library(doParallel)
library(sf)
library(spatialEco)

source("/data/notebooks/rstudio-adaptsampthomas/DECIDE_adaptivesampling/Scripts/modules/filter_distance.R")
source("/data/notebooks/rstudio-adaptsampthomas/DECIDE_adaptivesampling/Scripts/modules/recommend_rank.R")
source("/data/notebooks/rstudio-adaptsampthomas/DECIDE_adaptivesampling/Scripts/modules/recommend_metric.R")
source("/data/notebooks/rstudio-adaptsampthomas/DECIDE_adaptivesampling/Scripts/modules/recommend_agg_rank.R")
source("/data/notebooks/rstudio-adaptsampthomas/DECIDE_adaptivesampling/Scripts/modules/extract_metric.R")


#### Automated raster output loading
#' _input_:
#' taxa = 'butterfly', 'moth', 'orthoptera
#' model = 'lr', 'rf', 'gam' - later 'me'
#' 
#' _output_: raster stack of all the different model outputs
#' 'meanpred', 'quantilemaxmin', 'quantilerange' 


model = c('rf', 'lr', 'gam')
taxa = 'moth'

# get a list of all the species that appear in the outputs
spp_names_lr <- unique(gsub(pattern="lr_SDMs_|_meanpred.grd|_quantilemaxmin.grd|_quantilerange.grd", replacement = '', 
                            x = list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/lr'), pattern = '.grd')))

spp_names_rf <- unique(gsub(pattern="rf_SDMs_|_meanpred.grd|_quantilemaxmin.grd|_quantilerange.grd", replacement = '', 
                            x = list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/rf'), pattern = '.grd')))

spp_names_gam <- unique(gsub(pattern="gam_SDMs_|_meanpred.grd|_quantilemaxmin.grd|_quantilerange.grd", replacement = '', 
                             x = list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/gam'), pattern = '.grd')))

names <- unique(c(spp_names_lr, spp_names_rf, spp_names_gam))

# sdm outputs for each species
species_stack <- list()

# error outputs
error_out <- list()

for(i in 1:length(names)){
  
  print(names[i])
  
  # initiate model list within for loop so that it gets replaced when starting a new species
  # otherwise we might get some weird overlaps
  model_stack <- list()
  errored_models <- list()
  
  for(m in 1:length(model)){
    
    check_models <- list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/', model[m]), 
                               pattern = paste0(names[i]),
                               full.names = TRUE)
    
    if(length(check_models)<=1){
      
      print(paste('!!!   model', model[m], 'failed for species', names[i], '  !!!'))
      
      errored_models[[m]] <- data.frame(taxa = taxa, 
                                        species = names[i], 
                                        model = model[m])
      
      next
    }
    
    # mean predictions
    mp <- list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/', model[m]), 
                     pattern = paste0(names[i], "_meanpred.grd"),
                     full.names = TRUE)
    
    mod_preds <- raster::stack(mp)
    names(mod_preds) <- paste0(names[i], '_', model[m],'_mean_pred')
    
    
    
    # quantile min/max
    mm <- list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/', model[m]), 
                     pattern = paste0(names[i], "_quantilemaxmin.grd"),
                     full.names = TRUE)
    
    qminmax <- raster::stack(mm)
    names(qminmax) <- c(paste0(names[i], '_', model[m],'_min'), paste0(names[i], '_', model[m],'_max'))
    
    
    # quantile range
    qr <- list.files(paste0('/data-s3/thoval/sdm_outputs/', taxa, '/', model[m]), 
                     pattern = paste0(names[i], "_quantilerange.grd"),
                     full.names = TRUE)
    
    qrange <- raster::stack(qr)
    names(qrange) <- paste0(names[i], '_', model[m], '_quantile_range')
    
    
    # stack all from one model together
    model_stack[[m]] <- raster::stack(mod_preds, qminmax, qrange)
    
  }
  
  # model_stack[sapply(model_stack,is.null)] <- raster(nrow=12500, 
  #                                                    ncol=7000,
  #                                                    crs="+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +units=m +no_defs")
  
  # To combine them together need to remove the NULL raster layers (i.e. if a model hasn't worked)
  model_stack <- model_stack[!sapply(model_stack,is.null)]
  
  species_stack[[i]] <- raster::stack(model_stack)
  
  # Output the models that failed too
  error_out[[i]] <- do.call('rbind', errored_models) 
  
}


errors <- do.call('rbind', error_out)
errors

##  create a 'counts' raster layer  
dfm <- read.csv('Data/species_data/moth/DayFlyingMoths_East_Norths.csv')
head(dfm)

xy <- dfm[,c("lon","lat")]
spdf.moth <- SpatialPointsDataFrame(coords = xy, data = dfm,
                                    proj4string = CRS("+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +units=m +no_defs")) 

# plot(spdf.moth) ## check with plot

### create temporary raster to store number of records in each cell ###
moth_counts <- species_stack[[1]][[1]] # get a single raster

# make a raster of zeroes for input
moth_counts[!is.na(moth_counts)] <- 0
# get the cell index for each point and make a table:
counts = table(cellFromXY(moth_counts,spdf.moth))
# fill in the raster with the counts from the cell index:
moth_counts[as.numeric(names(counts))] <- counts
plot(moth_counts)



#####     Kernel density analyses    #####

## with spatstat package
library(spatstat)
moth_ppp <- ppp(x = dfm[,c("lon")], y = dfm[,c("lat")],
                owin(xrange = c(extent(moth_counts)[1], extent(moth_counts)[2]),
                     yrange = c(extent(moth_counts)[3], extent(moth_counts)[4])))


dp <- density(moth_ppp, sigma = 1000) # sigma = 1000 means that it is summarised per 1000m
plot(dp)

dpr <- raster(dp)
plot(dpr)

re_dpr <- resample(dpr, moth_counts, method = 'ngb')
plot(re_dpr)

kernel_moth <- mask(re_dpr, moth_counts)
plot(kernel_moth)
# contour(kernel_moth, add = TRUE)

# 
# # turn into a function
# density_points <- function(sp_data, surface, agg_dist) {
# 
#   # convert to ppp then raster
#   ppp_rast <- raster(ppp(x = sp_data[,c("lon")], y = sp_data[,c("lat")],
#                          owin(xrange = c(extent(surface)[1], extent(surface)[2]),
#                               yrange = c(extent(surface)[3], extent(surface)[4]))))
# 
# 
# 
# 
# 
# }

t <- stack(species_stack[[1]][[c(1, 4)]], kernel_moth)
tdf <- as.data.frame(t)

tdf2 <- na.omit(tdf)
head(tdf2)

### subsample to reduce
ind <- sample(c(1:dim(tdf2)[1]), size = 1000)

tdf2 <- tdf2[ind,]

library(plotly)
p <- plot_ly(x=tdf2$Adscita_geryon_rf_mean_pred, y=tdf2$Adscita_geryon_rf_quantile_range, z=tdf2$layer, color = tdf2$Adscita_geryon_rf_quantile_range, type="scatter3d", mode="markers")
p



td_mat <- as.matrix(tdf2)

plot_ly(z = ~td_mat) %>% add_surface()

# with spatialEco package
sd_m <- SpatialPoints(coords = dfm[,c("lon","lat")],
                      proj4string = CRS("+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +units=m +no_defs")) 

ag_moths <- aggregate(moth_counts, fact = 10)
plot(ag_moths)

kd_moth <- sp.kde(x = sd_m, bw = 10000, 
                  newdata = moth_counts)
plot(kd_moth, xlim = c(400000, 500000), ylim = c(500000, 600000))



##

## create metric for all species
sp <- species_stack[[1]]
m_pred_av <- calc(subset(sp, grep(pattern = 'mean_pred',
                                  names(sp))), mean, na.rm = T)

m_quant_av <- calc(subset(sp, grep(pattern = 'quantile_range',
                                   names(sp))), mean, na.rm = T)

plot(m_pred_av)
plot(m_quant_av)

# do for all species?
# want to see what wallingford looks like for all species
# so, first need to crop the rasters to a specific area

registerDoParallel(7)

# out_cropped <- list()

out_cropped <- foreach(s = 1:length(species_stack)) %dopar% {
  
  print(s)
  
  sp <- species_stack[[s]]
  
  # set location and distances
  location = c(-1.110557, 51.602436)
  distance = 5000
  
  # crop the prediction
  crop_pred <- filter_distance(obj = subset(sp, grep(pattern = 'mean_pred',
                                                     names(sp))),
                               method = 'buffer',
                               distance = distance,
                               location = location)
  
  # crop the error
  crop_err <- filter_distance(obj = subset(sp, grep(pattern = 'mean_pred',
                                                    names(sp))),
                              method = 'buffer',
                              distance = distance,
                              location = location)
  
  if(length(names(m_pred_av))>1){
    # get the mean
    m_pred_av <- calc(crop_pred,
                      mean, na.rm = T)
    names(m_pred_av) <- 'predictions'
    
    
    m_quant_av <- calc(crop_err,
                       mean, na.rm = T)
    names(m_quant_av) <- 'error'
  } else {
    
    m_pred_av <- crop_err
    m_quant_av <- crop_err
    
  }
  
  # out_cropped[[s]] <- 
  return(list(m_pred_av, m_quant_av))
  
}

registerDoSEQ()

# add the metrics together (for now)
additive_metric <- recommend_metric(prediction_raster = crop_pred,
                                    error_raster = crop_err,
                                    method = 'additive')$additive
