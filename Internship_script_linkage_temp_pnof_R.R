## spatial linkage of temperature to SSDs.


# set library and work directory:
.libPaths("[personal folder]//Libraries")
setwd("[personal folder]//Final_script_linkage")
# load necessary packages:
library(gstat)
library(RgoogleMaps)
library(GISTools)
library(raster)
library(rgdal)
library(sp)
library(shapefiles)
library(mapplots)
library(caTools)
library(fields)


## Overview of the script:
## PART 1 - SPATIAL POINT MAPS OF TEMPERATURE.
## PART 2 - SPATIAL GRID EXTENT.
## PART 3 - VARIOGRAPHY AND KRIGING INTERPOLATION.
## PART 4 - COLLECTING INTERPOLATION ACCURACY DATA.
## PART 5 - TRANSLATION OF TEMPERATURE TO PNOF VALUES.


#### PART 1 - SPATIAL POINT MAPS OF TEMPERATURE.


## The first step is to create spatial point maps for temperature values. This requires data from field measurements of temperature. 
# First, we retrieve the data.
Meuse1_10cm  <- read.csv("[name of first dataset].csv")
Meuse1_50cm  <- read.csv("[name of second dataset].csv")
Meuse1_100cm <- read.csv("[name of third dataset].csv")
## These datasets contain the data for spatial points with temperature values. We can now turn these into spatial points, and afterwards interpolate the values. Before we create the spatial data, we must split each dataset into two groups: one group of 80% and one group of 20%, using random selection of points. The large 80% group is called "Train" and the small 20% group is called "Test". These two groups are necessary to assess the interpolation accuracy, which is explained later on.
# Split randomly into 80% and 20%:
Meuse1_10cm$Train  <- sample.split(Meuse1_10cm$Tmax,  SplitRatio = 32) # 80% = 32 points
Meuse1_50cm$Train  <- sample.split(Meuse1_50cm$Tmax,  SplitRatio = 32) # 80% = 32 points
Meuse1_100cm$Train <- sample.split(Meuse1_100cm$Tmax, SplitRatio = 28) # 80% = 28 points
# Subset Train and Test groups:
Meuse1_10cm_train  <- subset(Meuse1_10cm,  Train=="TRUE",  select = c(1:4))
Meuse1_10cm_test   <- subset(Meuse1_10cm,  Train=="FALSE", select = c(1:4))
Meuse1_50cm_train  <- subset(Meuse1_50cm,  Train=="TRUE",  select = c(1:4))
Meuse1_50cm_test   <- subset(Meuse1_50cm,  Train=="FALSE", select = c(1:4))
Meuse1_100cm_train <- subset(Meuse1_100cm, Train=="TRUE",  select = c(1:4))
Meuse1_100cm_test  <- subset(Meuse1_100cm, Train=="FALSE", select = c(1:4))
# Convert to spatial data with Long and Lat as x- and y-coordinates:
coordinates(Meuse1_10cm)        = ~Long + Lat
coordinates(Meuse1_10cm_train)  = ~Long + Lat
coordinates(Meuse1_10cm_test)   = ~Long + Lat
coordinates(Meuse1_50cm)        = ~Long + Lat
coordinates(Meuse1_50cm_train)  = ~Long + Lat
coordinates(Meuse1_50cm_test)   = ~Long + Lat
coordinates(Meuse1_100cm)       = ~Long + Lat
coordinates(Meuse1_100cm_train) = ~Long + Lat
coordinates(Meuse1_100cm_test)  = ~Long + Lat
## Now we have spatial point maps, and we can now interpolate the temperature values of each map.


#### END OF PART 1 - SPATIAL POINT MAPS OF TEMPERATURE.


#### PART 2 - SPATIAL GRID EXTENTS.


## For interpolation, we need to create an underlying grid that serves as extent for the interpolation. This grid will have the same coordinates as the temperature maps. 
# Retrieve coordinates:
summary(Meuse1_10cm)
min(Meuse1_10cm$Long)
max(Meuse1_10cm$Long)
min(Meuse1_10cm$Lat)
max(Meuse1_10cm$Lat)
## longitude coords (x-values) range from 5.011 to 5.027
## latitude coords (y-values) range from 50.001 to 50.071
## Now we use these values as boundaries to create a new grid, dividing latitude and longitude into pieces with 0.0001 spacing between.
# Longitude: take all x-values and repeat each x-value with the number of y-values:
Meuse_10cm_extent_x = rep(seq(5.011,5.027,0.0001),each=701)
length(Meuse_10cm_extent_x)
# Latitude: take all y-values and repeat them as a whole with the number of x-values:
Meuse_10cm_extent_y = rep(seq(50.001,50.071,0.0001),161)
length(Meuse_10cm_extent_y)
## 161 horizontal (longitudinal) grid cells, repeated 701 times vertically.
## 701 vertical (lateral) grid cells, repeated 161 times horizontally.
## 161*701 = 112861 grid cells in total. 
# Use these long&lat values as coordinates to create a new dataframe:
Meuse_10cm_extent <- data.frame(xc = Meuse_10cm_extent_x, yc = Meuse_10cm_extent_y, z = c(1:112861)) # z-value = total number of grid cells.
coordinates(Meuse_10cm_extent) = ~xc+yc
gridded(Meuse_10cm_extent) = TRUE
Meuse_10cm_extent <- as(Meuse_10cm_extent, "SpatialGridDataFrame")
summary(Meuse_10cm_extent)
image(Meuse_10cm_extent["z"])
## Now we have a grid of 161*701 = 112861 cells across the spatial points, ready to use for interpolation. 


#### END OF PART 2 - SPATIAL GRID EXTENTS.


#### PART 3 - VARIOGRAPHY AND KRIGING INTERPOLATION.


## Interpolation will be performed with Kriging, which requires geostatistics/variography. 
## (Semi)Variogram models contain a nugget, range and sill. At a certain distance, the model flattens (dy=0). The distance (value on the x-axis) where the model first flattens is called the range, and the semivariance at that distance (value on the y-axis) is called the sill. Pairs of locations with separating distances smaller than the range have spatial autocorrelation (increasing model slope, dy/dx>0). The nugget is the semivariance at zero distance, so the intercept with the y-axis.
## First, lets create a variogram model for the first temperature map (Meuse1_10cm). Interpolation will be performed using the Train (80%) group of each map, so we use the Train groups for geostatistics and interpolation.
# Variogram:
Meuse1_10cm_vario  <- variogram(Tmax ~ 1, Meuse1_10cm_train)
plot(Meuse1_10cm_vario)
## The nugget is around 0.001,
## The range is around 0.023, and 
## The sill is around 0.010.
## Now we fit the variogram to a model. Initial values for the fitted model are needed, because fitting the range parameter involves non-linear regression:
Meuse1_10cm_v.fit <- fit.variogram(Meuse1_10cm_vario, vgm(1, "Sph", 0.023, 1))
Meuse1_10cm_v.fit
plot(Meuse1_10cm_vario, model=Meuse1_10cm_v.fit)
## The model is suboptimal to the variogram. Optimization of the parameters requires additional knowledge on geostatistics.
## Now we repeat these variography steps for the other maps.
# Variography Meuse1_50cm:
Meuse1_50cm_vario   <- variogram(Tmax ~ 1, Meuse1_50cm_train)
plot(Meuse1_50cm_vario)
Meuse1_50cm_v.fit <- fit.variogram(Meuse1_50cm_vario, vgm(1, "Sph", 0.024, 1))
Meuse1_50cm_v.fit
plot(Meuse1_50cm_vario, model=Meuse1_50cm_v.fit)
# Variography Meuse1_100cm:
Meuse1_100cm_vario   <- variogram(Tmax ~ 1, Meuse1_100cm_train)
plot(Meuse1_100cm_vario)
Meuse1_100cm_v.fit <- fit.variogram(Meuse1_100cm_vario, vgm(1, "Sph", 0.02, 1))
Meuse1_100cm_v.fit
plot(Meuse1_100cm_vario, model=Meuse1_100cm_v.fit)
## These models can now be used for kriging interpolation.


## Kriging requires the temperature maps, the corresponding fitted variogram models, and the grid extent. 
Meuse1_10cm_krig  <- krige(Tmax ~ 1, Meuse1_10cm_train,  Meuse_10cm_extent,  Meuse1_10cm_v.fit) # ordinary kriging
Meuse1_50cm_krig  <- krige(Tmax ~ 1, Meuse1_50cm_train,  Meuse_10cm_extent,  Meuse1_50cm_v.fit)
Meuse1_100cm_krig <- krige(Tmax ~ 1, Meuse1_100cm_train, Meuse_100cm_extent, Meuse1_100cm_v.fit)
as.data.frame(Meuse1_10cm_krig)[1:5,]
spplot(Meuse1_10cm_krig, "var1.pred", main = "Meuse1_10cm_krig", colorkey=T) # colorkey=T for continuous values.
## The interpolation values are stored as var1.pred. The interpolation variances are stored as var1.var. These variances are derived from the statistical model and give an indication of the reliability of the estimates.
## Now we have three spatial maps with interpolated temperature data. These temperature maps can now be assessed for accuracy and translated to PNOF values.


#### END OF PART 3 - GEOSTATISTICS AND KRIGING INTERPOLATION.


#### PART 4 - COLLECTING INTERPOLATION ACCURACY DATA.


## Kriging accuracy is assessed by comparing the Test groups (spatial points) with the kriging values at the same location. Thus, the test values and corresponding interpolation values will be collected and exported.
# Transform kriging spatialGRIDdataframes to kriging rasters:
summary(Meuse1_10cm_krig)
Meuse1_10cm_krig_ras  <- raster(Meuse1_10cm_krig,  layer=1) # layer=1 -> use values of column 1 (interpolation values).
Meuse1_50cm_krig_ras  <- raster(Meuse1_50cm_krig,  layer=1)
Meuse1_100cm_krig_ras <- raster(Meuse1_100cm_krig, layer=1)
# Create new dataframes that include Test coordinates, original Test values and Extract-points-from-raster values:
Meuse1_10cm_test_krig  <- data.frame(coordinates(Meuse1_10cm_test),  Meuse1_10cm_test$Tmax,  extract(Meuse1_10cm_krig_ras, Meuse1_10cm_test))
Meuse1_50cm_test_krig  <- data.frame(coordinates(Meuse1_50cm_test),  Meuse1_50cm_test$Tmax,  extract(Meuse1_50cm_krig_ras, Meuse1_50cm_test))
Meuse1_100cm_test_krig <- data.frame(coordinates(Meuse1_100cm_test), Meuse1_100cm_test$Tmax, extract(Meuse1_100cm_krig_ras, Meuse1_100cm_test))
# Customize column names:
names(Meuse1_10cm_test_krig)  <- c("xc", "yc", "Test", "Krig")
names(Meuse1_50cm_test_krig)  <- c("xc", "yc", "Test", "Krig")
names(Meuse1_100cm_test_krig) <- c("xc", "yc", "Test", "Krig")
summary(Meuse1_10cm_test_krig)
nrow(Meuse1_10cm_test_krig)
## xc = Longitude, yc = Latitude, Test = temperature value from not interpolated Test group, Krig = temperature value from interpolated map for the corresponding Test point value. These values can now be exported.
# Export to CSV:
write.csv(Meuse1_10cm_test_krig,  file="[personal folder]//Meuse1_10cm_test_krig.csv")
write.csv(Meuse1_50cm_test_krig,  file="[personal folder]//Meuse1_50cm_test_krig.csv")
write.csv(Meuse1_100cm_test_krig, file="[personal folder]//Meuse1_100cm_test_krig.csv")
## Now we have exported tables with the temperature test data and the corresponding kriging values.


#### END OF PART 4 - COLLECTING INTERPOLATION ACCURACY DATA.


#### PART 5 - TRANSLATION OF TEMPERATURE TO PNOF VALUES.


## Now we create new dataframes and translate the interpolated temperature values to PNOF values using an SSD formula for fish in the Meuse. 
# Extract kriging data to new dataframes:
summary(Meuse1_10cm_krig)
Meuse1_10cm_temp_pnof  <- as.data.frame(Meuse1_10cm_krig)
Meuse1_50cm_temp_pnof  <- as.data.frame(Meuse1_50cm_krig)
Meuse1_100cm_temp_pnof <- as.data.frame(Meuse1_100cm_krig)
# Select columns:
summary(Meuse1_10cm_temp_pnof)
Meuse1_10cm_temp_pnof  <- Meuse1_10cm_temp_pnof[,c(3,4,1)]
Meuse1_50cm_temp_pnof  <- Meuse1_50cm_temp_pnof[,c(3,4,1)]
Meuse1_100cm_temp_pnof <- Meuse1_100cm_temp_pnof[,c(3,4,1)]
# Duplicate temperature columns:
Meuse1_10cm_temp_pnof$Pnof  <- Meuse1_10cm_temp_pnof$var1.pred
Meuse1_50cm_temp_pnof$Pnof  <- Meuse1_50cm_temp_pnof$var1.pred
Meuse1_100cm_temp_pnof$Pnof <- Meuse1_100cm_temp_pnof$var1.pred
# Change column names:
colnames(Meuse1_10cm_temp_pnof)  <- c("x", "y", "Tmax", "Pnof")
colnames(Meuse1_50cm_temp_pnof)  <- c("x", "y", "Tmax", "Pnof")
colnames(Meuse1_100cm_temp_pnof) <- c("x", "y", "Tmax", "Pnof")
summary(Meuse1_10cm_temp_pnof)
## Now we are going to translate the values in the "Pnof" columns by inserting the fish SSD formula. The fish SSD is created through fitting a normal distribution which calculates the PNOF values based on the measured water temperature.
# Insert SSD with pnorm():
Meuse1_10cm_temp_pnof$Pnof  <- pnorm(Meuse1_10cm_temp_pnof$Pnof,  mean=26.6739, sd=6.3318) # Meuse fish SSD
Meuse1_50cm_temp_pnof$Pnof  <- pnorm(Meuse1_50cm_temp_pnof$Pnof,  mean=26.6739, sd=6.3318) # Meuse fish SSD
Meuse1_100cm_temp_pnof$Pnof <- pnorm(Meuse1_100cm_temp_pnof$Pnof, mean=26.6739, sd=6.3318) # Meuse fish SSD
# Transform to SpatialPointsDataFrame:
coordinates(Meuse1_10cm_temp_pnof)  = ~x + y
coordinates(Meuse1_50cm_temp_pnof)  = ~x + y
coordinates(Meuse1_100cm_temp_pnof) = ~x + y
# Change spatialPOINTSdataframe to spatialPIXELSdataframe:
Meuse1_10cm_temp_pnof  = as(Meuse1_10cm_temp_pnof,  "SpatialPixelsDataFrame")
Meuse1_50cm_temp_pnof  = as(Meuse1_50cm_temp_pnof,  "SpatialPixelsDataFrame")
Meuse1_100cm_temp_pnof = as(Meuse1_100cm_temp_pnof, "SpatialPixelsDataFrame")
# Change spatialPIXELSdataframe to spatialGRIDdataframe:
Meuse1_10cm_temp_pnof  = as(Meuse1_10cm_temp_pnof,  "SpatialGridDataFrame")
Meuse1_50cm_temp_pnof  = as(Meuse1_50cm_temp_pnof,  "SpatialGridDataFrame")
Meuse1_100cm_temp_pnof = as(Meuse1_100cm_temp_pnof, "SpatialGridDataFrame")
summary(Meuse1_10cm_temp_pnof)
# Lets see one of the spatial maps:
spplot(Meuse1_10cm_temp_pnof, "Tmax", main = "Meuse1_10cm_temp_pnof", at=(920:980)/50) # colorkey=T for continuous values.
spplot(Meuse1_10cm_temp_pnof, "Pnof", main = "Meuse1_10cm_temp_pnof", at=(192:262)/2000)
## Now we have three spatial maps with temperature and PNOF values.
# Export to CSV:
write.csv(Meuse1_10cm_temp_pnof,  file="[personal folder]//Meuse1_10cm_temp_pnof.csv")
write.csv(Meuse1_50cm_temp_pnof,  file="[personal folder]//Meuse1_50cm_temp_pnof.csv")
write.csv(Meuse1_100cm_temp_pnof, file="[personal folder]//Meuse1_100cm_temp_pnof.csv")
## Now we have exported tables with the temperature and PNOF data for all three maps.


#### END OF PART 5 - TRANSLATION OF TEMPERATURE TO PNOF VALUES.


#### PART 6 - QUANTIFICATION OF FISH PNOF VALUES.


## Now we are going to quantify the fish PNOF values of the spatial maps. To do this, we divide the fish PNOF values into categories with a small value range per category.
## First, we must transform the spatial dataframes back to normal dataframes: 
Meuse1_10cm_krig  <- as.data.frame(Meuse1_10cm_krig)
Meuse1_50cm_krig  <- as.data.frame(Meuse1_50cm_krig)
Meuse1_100cm_krig <- as.data.frame(Meuse1_100cm_krig)
## Now let's analyse the total fish PNOF value range: 
summary(Meuse1_10cm_temp_pnof$Fish)
summary(Meuse1_50cm_temp_pnof$Fish)
summary(Meuse1_100cm_temp_pnof$Fish)
## total value range fish PNOF = 0.09617-0.1303.
## For quantification, we divide this total fish PNOF value range into 35 categories with a value range of 0.001 PNOF per category. 
## Now let's quantify each of the three datasets. 
# 10cm:
summary(Meuse1_10cm_temp_pnof)
Meuse1_fish_quant_10cm <- as.data.frame(Meuse1_10cm_temp_pnof)
summary(Meuse1_fish_quant_10cm)
nrow(Meuse1_fish_quant_10cm)
min(Meuse1_fish_quant_10cm$Fish)
max(Meuse1_fish_quant_10cm$Fish)
## all Meuse1_10cm fish PNOF values are between 0.1015602 and 0.1185163 --> categories 6-24.
# use a nested ifelse function for quantification: 
Meuse1_fish_quant_10cm$Cat_10cm <- ifelse(Meuse1_fish_quant_10cm$Fish>0.118, "24", 
                                          ifelse(Meuse1_fish_quant_10cm$Fish>0.117 & Meuse1_fish_quant_10cm$Fish<=0.118, "23", 
                                                 ifelse(Meuse1_fish_quant_10cm$Fish>0.116 & Meuse1_fish_quant_10cm$Fish<=0.117, "22", 
                                                        ifelse(Meuse1_fish_quant_10cm$Fish>0.115 & Meuse1_fish_quant_10cm$Fish<=0.116, "21", 
                                                               ifelse(Meuse1_fish_quant_10cm$Fish>0.114 & Meuse1_fish_quant_10cm$Fish<=0.115, "20", 
                                                                      ifelse(Meuse1_fish_quant_10cm$Fish>0.113 & Meuse1_fish_quant_10cm$Fish<=0.114, "19", 
                                                                             ifelse(Meuse1_fish_quant_10cm$Fish>0.112 & Meuse1_fish_quant_10cm$Fish<=0.113, "18", 
                                                                                    ifelse(Meuse1_fish_quant_10cm$Fish>0.111 & Meuse1_fish_quant_10cm$Fish<=0.112, "17", 
                                                                                           ifelse(Meuse1_fish_quant_10cm$Fish>0.110 & Meuse1_fish_quant_10cm$Fish<=0.111, "16", 
                                                                                                  ifelse(Meuse1_fish_quant_10cm$Fish>0.109 & Meuse1_fish_quant_10cm$Fish<=0.110, "15", 
                                                                                                         ifelse(Meuse1_fish_quant_10cm$Fish>0.108 & Meuse1_fish_quant_10cm$Fish<=0.109, "14", 
                                                                                                                ifelse(Meuse1_fish_quant_10cm$Fish>0.107 & Meuse1_fish_quant_10cm$Fish<=0.108, "13", 
                                                                                                                       ifelse(Meuse1_fish_quant_10cm$Fish>0.106 & Meuse1_fish_quant_10cm$Fish<=0.107, "12", 
                                                                                                                              ifelse(Meuse1_fish_quant_10cm$Fish>0.105 & Meuse1_fish_quant_10cm$Fish<=0.106, "11", 
                                                                                                                                     ifelse(Meuse1_fish_quant_10cm$Fish>0.104 & Meuse1_fish_quant_10cm$Fish<=0.105, "10", 
                                                                                                                                            ifelse(Meuse1_fish_quant_10cm$Fish>0.103174603 & Meuse1_fish_quant_10cm$Fish<=0.104,  "9", 
                                                                                                                                                   ifelse(Meuse1_fish_quant_10cm$Fish>0.103 & Meuse1_fish_quant_10cm$Fish<=0.103174603,  "8", 
                                                                                                                                                          ifelse(Meuse1_fish_quant_10cm$Fish>0.102 & Meuse1_fish_quant_10cm$Fish<=0.103,  "7", 
                                                                                                                                                                 ifelse(Meuse1_fish_quant_10cm$Fish>0.101 & Meuse1_fish_quant_10cm$Fish<=0.102,  "6", 
                                                                                                                                                                        "0")))))))))))))))))))
Meuse1_fish_quant_10cm$Cat_10cm    <- as.factor(Meuse1_fish_quant_10cm$Cat_10cm)
summary(Meuse1_fish_quant_10cm)
nrow(Meuse1_fish_quant_10cm)
nrow(subset(Meuse1_fish_quant_10cm, Cat_10cm==6))
## calculate percentages of each category and insert in excel table:
(nrow(subset(Meuse1_fish_quant_10cm, Cat_10cm==11))/nrow(Meuse1_fish_quant_10cm))*100
## Now we repeat this process for the other two datasets. 
# 50cm:
Meuse1_fish_quant_50cm <- as.data.frame(Meuse1_50cm_temp_pnof)
summary(Meuse1_fish_quant_50cm)
nrow(Meuse1_fish_quant_50cm)
min(Meuse1_fish_quant_50cm$Fish)
max(Meuse1_fish_quant_50cm$Fish)
## all Meuse1_50cm  values are between 0.09872617 and 0.101754 --> categories 3-6.
Meuse1_fish_quant_50cm$Cat_50cm <- ifelse(Meuse1_fish_quant_50cm$Fish>0.101, "6", 
                                          ifelse(Meuse1_fish_quant_50cm$Fish>0.100 & Meuse1_fish_quant_50cm$Fish<=0.101, "5", 
                                                 ifelse(Meuse1_fish_quant_50cm$Fish>0.099 & Meuse1_fish_quant_50cm$Fish<=0.100, "4", 
                                                        ifelse(Meuse1_fish_quant_50cm$Fish>0.098 & Meuse1_fish_quant_50cm$Fish<=0.099, "3", "0"))))
Meuse1_fish_quant_50cm$Cat_50cm    <- as.factor(Meuse1_fish_quant_50cm$Cat_50cm)
summary(Meuse1_fish_quant_50cm)
nrow(Meuse1_fish_quant_50cm)
nrow(subset(Meuse1_fish_quant_50cm, Cat_50cm==3))
## calculate percentages of each category and insert in excel table:
(nrow(subset(Meuse1_fish_quant_50cm, Cat_50cm==6))/nrow(Meuse1_fish_quant_50cm))*100
##
# 100cm:
Meuse1_fish_quant_100cm <- as.data.frame(Meuse1_100cm_temp_pnof)
summary(Meuse1_fish_quant_100cm)
nrow(Meuse1_fish_quant_100cm)
min(Meuse1_fish_quant_100cm$Fish)
max(Meuse1_fish_quant_100cm$Fish)
## all M2 100cm values are between 0.09616913 and 0.09913644 --> categories 1-3.
Meuse1_fish_quant_100cm$Cat_100cm <- ifelse(Meuse1_fish_quant_100cm$Fish>0.098, "3", 
                                            ifelse(Meuse1_fish_quant_100cm$Fish>0.097 & Meuse1_fish_quant_100cm$Fish<=0.098, "2", 
                                                   ifelse(Meuse1_fish_quant_100cm$Fish>0.096 & Meuse1_fish_quant_100cm$Fish<=0.097, "1", "0")))
Meuse1_fish_quant_100cm$Cat_100cm    <- as.factor(Meuse1_fish_quant_100cm$Cat_100cm)
summary(Meuse1_fish_quant_100cm)
nrow(Meuse1_fish_quant_100cm)
nrow(subset(Meuse1_fish_quant_100cm, Cat_100cm==1))
## calculate percentages of each category and insert in excel table:
(nrow(subset(Meuse1_fish_quant_100cm, Cat_100cm==3))/nrow(Meuse1_fish_quant_100cm))*100


#### END OF PART 6 - QUANTIFICATION OF FISH PNOF VALUES.


#### END OF THE SPATIAL LINKAGE.