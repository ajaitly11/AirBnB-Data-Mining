# ***** Prediction for Review Score Location ******
#install.packages("data.table")
#install.packages("caret")
#install.packages("ggplot2")
#install.packages("corrplot")
#install.packages("tree")
#install.packages("e1071")
#install.packages("leaps")
#install.packages("ModelMetrics")
install.packages("polywog")
install.packages("rpart.plot")
library(corrplot)
library(caret)
library(data.table)
library(ggplot2)
library(ModelMetrics)
library(polywog)
library (tree)
library(rpart.plot)
library(e1071)

#path = '/Users/admin/Downloads/listings.csv'
airbnb = fread(input = "listings.csv")
#airbnb = fread(input = path)

# ***** Preliminary Data Cleaning ******

blank_cols = c("neighbourhood_group_cleansed","calendar_updated","license")
# We will keep the bathroom column for now, as we can extract that data from bathrooms_text

# Removing Blank columns, note how the variables in our data frame drop from 74 to 71
airbnb = subset(airbnb, select = !(names(airbnb) %in% blank_cols))

#Lets store number of bathrooms in the blank column, by extracting data from the bathrooms_text column
airbnb$bathrooms = as.numeric(gsub('[a-zA-Z]', '', airbnb$bathrooms_text))

# Saving host_since as a individual variable
host_since =as.character(airbnb [["host_since"]])
# Calculate the joining time for each host
join_time = c()
for(i in 1: length(host_since )){
  join_time[i] = difftime("2021-12-09", strptime(host_since[i], format = "%Y-%m-%d"), ,unit = "days")
}
# Introduce join_time as a new column into data set
airbnb = cbind(airbnb,join_time)

# Lets remove columns not required for our analysis 
cols_to_be_removed = c("id","listing_url","scrape_id","last_scraped","name","description","neighborhood_overview",
                       "picture_url","host_id","host_url","host_name","host_since","host_about","host_thumbnail_url",
                       "host_picture_url","calendar_last_scraped", "first_review", "last_review", "bathrooms_text", 
                       "host_listings_count","neighbourhood","minimum_minimum_nights",
                       "maximum_minimum_nights","minimum_maximum_nights","maximum_maximum_nights",
                       "minimum_nights_avg_ntm","maximum_nights_avg_ntm")

airbnb = subset(airbnb, select = !(names(airbnb) %in% cols_to_be_removed))

# We see that some columns still have N/A values which are not being treated as such
# because R is reading them as strings, the following code helps us with that - 
airbnb[airbnb=="N/A"] = NA

# We also have some blank values in some columns that should be converted to NA as well
airbnb[airbnb == "" | airbnb == " "] = NA 

# Check NA values as a percentage of total data again 
hist(colMeans(is.na(airbnb)),
     labels = TRUE,
     col = "darkblue",
     main = "NA Values as a percentage of Data",
     xlab = "Mean NA Values",
     border = "white",
     ylim = c(0,65))

# removes listings with no stays or corrupted/incomplete reviews
airbnb = airbnb[!is.na(airbnb$review_scores_location) & 
                  !is.na(airbnb$review_scores_checkin) & 
                  !is.na(airbnb$review_scores_cleanliness) & 
                  !is.na(airbnb$review_scores_value),]

# turns all NA join times into the mean join time
airbnb$join_time[which(is.na(airbnb$join_time))] = mean(airbnb$join_time[which(!is.na(airbnb$join_time))])

# count number of verification ways
#install.packages("BBmisc")
library(BBmisc)
verification = airbnb [,c("host_verifications")]
counts_verification = c()
for (i in 1: dim(verification)[1]){
  a = toString(verification[i])
  counts_verification[i] = length(explode( a,','))
}
airbnb = cbind(airbnb,counts_verification)


# count number of amenities
amenities = airbnb [,c("amenities")]
counts_amenities = c()
for (i in 1: dim(amenities)[1]){
  a = toString(amenities[i])
  counts_amenities[i] = length(explode( a,','))
}
airbnb = cbind(airbnb,counts_amenities)

# *** More Data Cleaning ***


# Clean verifications & amenities and count unique
unique_verifications = gsub("[[:punct:]]","",unlist(strsplit(airbnb$host_verifications,split=",")))
unique_verifications = unique(unique_verifications)

clean_host_verifications = strsplit(gsub("[[:punct:]]","",airbnb$host_verifications), split = " ")
airbnb = airbnb[,-c("host_verifications")]

unique_amenities = gsub("[[:punct:]]","",unlist(strsplit(airbnb$amenities,split=",")))
temp = as.factor(unique_amenities) # store factor information before we change unique_amenities
unique_amenities = unique(unique_amenities)

clean_amenities = strsplit(gsub("[[:punct:]]","",airbnb$amenities), split = " ")
airbnb = airbnb[,-c("amenities")]

summary = summary(temp)
for (i in 1:90) { # remove white space that R introduced
  if(substring(names(summary)[i],1,1)==" ") {
    names(summary)[i] = substring(names(summary)[i],2)
  }
}
keepT90 = names(summary)[1:90] # top 90 most frequent ammenities
keepT90 = keepT90[-c(29,32,38,74)] # remove duplicate shampoo washer Hot water heating

# keep only top 90 amenities and discard the rest
for (i in 1:length(clean_amenities)) {
  temp_index = clean_amenities[[i]][1:length(clean_amenities[[i]])] %in% keepT90
  clean_amenities[[i]] = clean_amenities[[i]][temp_index]
}

#### Another way to split amentites cols ###
# Extract amenities from airbnb data set
airbnb_amenities = airbnb [,c("amenities")]

# Generate a long list of all strings below this cols; Run slowly-around 3 minutes
install.packages("BBmisc")
library(BBmisc)
total_amenities = c()
for ( i in 1: dim(airbnb_amenities)[1]){
  a = airbnb_amenities[i,]
  a = toString(a)
  a = explode( a,',')
  c =  gsub("\\[","",a)
  c =  gsub("\\]","",c)
  c = gsub('"',' ',c)
  total_amenities = c(total_amenities,c)
}

# Select top 10 most frequent cases
table1 = data.frame (total_amenities)
w = table(total_amenities)
w1 = data.frame (w)
w2 <- w1[order(w1$Freq, decreasing = TRUE), ]
top_10 = w2$total_amenities[1:10]

# convert to dummy
# create temporary table first of all 0s for every dummy
temp_table = airbnb[,1:2]
temp_table[ , keepT90] <- c(0)
temp_table = temp_table[,3:length(temp_table[1])]

# for every amenity go to the appropriate dummy column and turn that 
# flat's value to 1
for (i in 1:length(clean_amenities)) {
  for (j in clean_amenities[[i]]){
    #if (i %% 1000 == 0) {print(i)}
    temp_table[[j]][i] = 1 
  }
}
# attach the dummy columns to main data table
airbnb = cbind(airbnb,temp_table)


# Location score analysis
set.seed(1)
airbnb_location = airbnb[,c("latitude","longitude","review_scores_location")]
colMeans(is.na(airbnb_location)) # no missing value
summary(airbnb_location)


# Divide into test dataset 30% and training dataset 70%
test_set_indices = sample(1:nrow(airbnb_location),round(0.3*nrow(airbnb_location)),replace = FALSE)
training_set = airbnb_location[-test_set_indices,]
test_set = airbnb_location[test_set_indices,]

# EDA
hist(training_set$latitude, main = "Histogram of latitude", xlab = "latitude") 
# lookes like normal distribution

hist(training_set$longitude,main = "Histogram of longitude", xlab = "longitude")
# looks like normal distribution

hist(training_set$review_scores_location,main = "Histogram of location score", xlab = "location score")
# skewed to the right, needs some transformation
# taking log as log_location = log(training_set$review_scores_location)
log_location = log(training_set$review_scores_location)
hist(log_location,main = "Histogram of log(location score)", xlab = "log(location score)")
# still not normal

pairs(airbnb_location) 
corrplot(cor(airbnb_location), method = "circle", diag = FALSE,type = "upper")
# shows that 1) latitute is positively correlated with longitude
# 2) latitute does not correlated with location score
# 3) longitute is slightly negatively correlated with location score


# Fit in linear regession model
lm_reg = train(review_scores_location ~ latitude + longitude,
                data = training_set, method = 'lm',
                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
                preProcess = c('center','scale'))
lm_reg$finalModel
# Result is consistent with correlation table, showing that latitude does not play a significant role # in the model and longitude is negatively related to the location score.
# linear model is location score = -0.026123*scale(longitude)+0.002919*scale(latitude)+4.746319
# it is not a good model since r square is almost zero, which means it doesn't explain any variation
# rmse = 0.4341842 for training set
rmse(test_set$review_scores_location,predict(lm_reg,test_set[,c("latitude","longitude"),drop=FALSE])) # rmse = 0.4009447 for testing set            
par(mfrow=c(2,2))
plot(lm_reg$finalModel) # implies residual is not normally distributed，thus confirmed that this model doesn't explain.

# Model selection
regfit_full = regsubsets(review_scores_location~. , data=training_set)
summary_full = summary(regfit_full)
plot(summary_full$rss,type="b")
lm_reg_onlyl = train(review_scores_location ~ longitude,
                data = training_set, method = 'lm',
                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
                preProcess = c('center','scale'))
# rmse = 0.4340705 for training set
rmse(test_set$review_scores_location,predict(lm_reg_onlyl,test_set[,c("latitude","longitude"),drop=FALSE]))
# rmse = 0.4009162 for test set
par(mfrow=c(2,2))
plot(lm_reg_onlyl$finalModel) # still pretty bed

# Since log0 is undefined, we will add 1 to each score to avoid it.
lm2_reg = train(log(review_scores_location+1) ~ latitude + longitude,
                data = training_set, method = 'lm',
                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
                preProcess = c('center','scale'))
lm2_reg
summary(lm2_reg$finalModel)
rmse(log(test_set$review_scores_location+1),predict(lm2_reg,test_set[,c("latitude","longitude"),drop=FALSE]))
plot(lm2_reg$finalModel)
# rmse = 0.1017434  for training set; rmse =  0.08886645 for testing set;plot still bad:heavy tails

# try polynomial regression
poly_reg = cv.polywog(review_scores_location ~ scale(latitude) + scale(longitude),
                data = training_set, degrees.cv = 1:20,
                nfolds = 10,thresh = 1e-4)
poly_reg$degree.min # the best degree is 6
poly_reg$polywog.fit
poly_reg_model<- bootPolywog(poly_reg$polywog.fit, nboot = 3)
rmse(test_set$review_scores_location,predict(poly_reg_model,test_set[,c("latitude","longitude"),drop=FALSE])) # rmse = 0.3961075 for test set
rmse(training_set$review_scores_location,predict(poly_reg_model,training_set[,c("latitude","longitude"),drop=FALSE])) # rmse = 0.4283884 for traininng set
plot(poly_reg_model)


## Decision Tree - Regression
# initial idea of tree
tree_location <- tree (review_scores_location~. , data=training_set)
summary(tree_location )
plot (tree_location)
text (tree_location , pretty = 0)
# cv to choose the best tree
cp.grid = expand.grid(.cp = (0:10)*0.001)
tree_reg = train(review_scores_location ~ latitude + longitude,
                data = training_set, method = 'rpart',
                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
                tuneGrid = cp.grid )
tree_reg 
best.tree = tree_reg$finalModel
prp(best.tree) # the best cp is 0.001                
mean ((predict (best.tree , newdata =training_set) - training_set$review_scores_location)^2) 
# training data: mse = 0.1781331; rmse = 0.4220582
mean ((predict (best.tree , newdata =test_set) - test_set$review_scores_location)^2)  
# testing data: mse = 0.1378898; rmse = 0.3713352


## SVM Regression: choose radial kernel
library(caret)
#install.packages("kernlab")
#library(kernlab)
#svm_reg_linear = train(review_scores_location ~ latitude + longitude,
#                data = training_set, method = 'svmRadial',
#                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
#                preProcess = c('center','scale'),
#                 tuneGrid = expand.grid(C = seq(0, 1, length = 10),sigma = c(0.1,0.2)))
# Since data set is very large over 40000 instance, when I run the code for tuning parameter it doesn't work.

# fit in radial kernal 
plot(training_set[,1:2],col=training_set$review_scores_location+3,asp=0) 
# eps-regression: no control of number of support vectors
svmfit1 = svm(review_scores_location~. ,data=training_set, kernel="radial" ,scale=TRUE) # needs around 5 minutes to run
summary(svmfit1) 
# training set rmse = 0.4404114
rmse(training_set$review_scores_location,predict(svmfit1,training_set[,1:2])) 
# Testing set rmse = 0.4064776
rmse(test_set$review_scores_location,predict(svmfit1,test_set[,1:2]))

# fit in linear kernal svm regression
svmfit2 = svm(review_scores_location~. ,data=training_set, kernel="linear" ,scale=TRUE)
# training set rmse = 0.4533505
rmse(training_set$review_scores_location,predict(svmfit2,training_set[,1:2]))
# testing set rmse =0.4192826
rmse(test_set$review_scores_location,predict(svmfit2,test_set[,1:2]))

# fit in polynomial kernal svm regression
svmfit3 = svm(review_scores_location~. ,data=training_set, kernel="polynomial" ,scale=TRUE)
# training set rmse = 0.4537708
rmse(training_set$review_scores_location,predict(svmfit3,training_set[,1:2]))
# testing set rmse =  0.4199995
rmse(test_set$review_scores_location,predict(svmfit3,test_set[,1:2]))



## KNN Regression

tuneGrid = expand.grid(k = seq(1,59, by = 2))
#Warning - the next line of code takes about 8 minutes to execute
knn_reg = train(review_scores_location ~ latitude + longitude,
                data = training_set, method = 'knn',
                preProcess = c('center','scale'),
                trControl = trainControl(method = 'repeatedcv' , number = 10, repeats = 3),
                tuneGrid = tuneGrid)

knn_results = knn_reg$results #least rmse for k = 59
knn_results
plot(knn_reg)
varImp(knn_reg) #it is taking longitude to be the most important variable of importance, as seen above

pred_knn = predict(knn_reg, newdata = test_set)
RMSE(pred_knn,test_set$review_scores_location)
#Therefore, we get an RMSE value of 0.3891 on test set and RMSE value of 0.4224938 on training set

