# Including needed libraries

install.packages("qdap")
install.packages("XML")
install.packages("splitstackshape")
install.packages("caret")
install.packages("ranger")

library(ranger)
library(qdap)
library(XML)
library(tm)
library(splitstackshape)
library(caret)

start.time <- Sys.time()

# Preparing parameters
# n <- 10
n<-1000
lang <- "es"
path_training <- "C:\\Users\\mtebenga\\Social Media\\pan-ap17-bigdata\\training"		# Your training path
path_test <- "C:\\Users\\mtebenga\\Social Media\\pan-ap17-bigdata\\test"# Your test path
k <- 3
r <- 1

# Auxiliar functions
# * GenerateVocabulary: Given a corpus (training set), obtains the n most frequent words
# * GenerateBoW: Given a corpus (training or test), and a vocabulary, obtains the bow representation

# GenerateVocabulary: Given a corpus (training set), obtains the n most frequent words
GenerateVocabulary <- function(path, n = 1000, lowcase = TRUE, punctuations = TRUE, numbers = TRUE, whitespaces = TRUE, swlang = "", swlist = "", verbose = TRUE) {
  setwd(path)
  
  # Reading corpus list of files
  files = list.files(pattern="*.xml")
  
  # Reading files contents and concatenating into the corpus.raw variable
  corpus.raw <- NULL
  i <- 0
  for (file in files) {
    xmlfile <- xmlTreeParse(file, useInternalNodes = TRUE)
    corpus.raw <- c(corpus.raw, xpathApply(xmlfile, "//document", function(x) xmlValue(x)))
    i <- i + 1
    if (verbose) print(paste(i, " ", file))
  }
  
  # Preprocessing the corpus
  corpus.preprocessed <- corpus.raw
  
  if (lowcase) {
    if (verbose) print("Tolower...")
    corpus.preprocessed <- tolower(corpus.preprocessed)
  }
  
  if (punctuations) {
    if (verbose) print("Removing punctuations...")
    corpus.preprocessed <- removePunctuation(corpus.preprocessed)
  }
  
  if (numbers) {
    if (verbose) print("Removing numbers...")
    corpus.preprocessed <- removeNumbers(corpus.preprocessed)
  }
  
  if (whitespaces) {
    if (verbose) print("Stripping whitestpaces...")
    corpus.preprocessed <- stripWhitespace(corpus.preprocessed)
  }
  
  if (swlang!="")	{
    if (verbose) print(paste("Removing stopwords for language ", swlang , "..."))
    corpus.preprocessed <- removeWords(corpus.preprocessed, stopwords(swlang))
  }
  
  if (swlist!="") {
    if (verbose) print("Removing provided stopwords...")
    corpus.preprocessed <- removeWords(corpus.preprocessed, swlist)
  }
  
  # Generating the vocabulary as the n most frequent terms
  if (verbose) print("Generating frequency terms")
  corpus.frequentterms <- freq_terms(corpus.preprocessed, n)
  if (verbose) plot(corpus.frequentterms)
  
  return (corpus.frequentterms)
}

# GenerateBoW: Given a corpus (training or test), and a vocabulary, obtains the bow representation
GenerateBoW <- function(path, vocabulary, n = 100000, lowcase = TRUE, punctuations = TRUE, numbers = TRUE, whitespaces = TRUE, swlang = "", swlist = "", class="variety", verbose = TRUE) {
  setwd(path)
  
  # Reading the truth file
  truth <- read.csv("truth.txt", sep=":", header=FALSE)
  truth <- truth[,c(1,4,7)]
  colnames(truth) <- c("author", "gender", "variety")
  
  i <- 0
  bow <- NULL
  # Reading the list of files in the corpus
  files = list.files(pattern="*.xml")
  for (file in files) {
    # Obtaining truth information for the current author
    author <- gsub(".xml", "", file)
    variety <- truth[truth$author==author,"variety"]
    gender <- truth[truth$author==author,"gender"]
    
    # Reading contents for the current author
    xmlfile <- xmlTreeParse(file, useInternalNodes = TRUE)
    txtdata <- xpathApply(xmlfile, "//document", function(x) xmlValue(x))
    
    # Preprocessing the text
    if (lowcase) {
      txtdata <- tolower(txtdata)
    }
    
    if (punctuations) {
      txtdata <- removePunctuation(txtdata)
    }
    
    if (numbers) {
      txtdata <- removeNumbers(txtdata)
    }
    
    if (whitespaces) {
      txtdata <- stripWhitespace(txtdata)
    }
    
    # Building the vector space model. For each word in the vocabulary, it obtains the frequency of occurrence in the current author.
    line <- author
    freq <- freq_terms(txtdata, n)
    for (word in vocabulary$WORD) {
      thefreq <- 0
      if (length(freq[freq$WORD==word,"FREQ"])>0) {
        thefreq <- freq[freq$WORD==word,"FREQ"]
      }
      line <- paste(line, ",", thefreq, sep="")
    }
    
    # Concatenating the corresponding class: variety or gender
    if (class=="variety") {
      line <- paste(variety, ",", line, sep="")
    } else {
      line <- paste(gender, ",", line, sep="")
    }
    
    # New row in the vector space model matrix
    bow <- rbind(bow, line)
    i <- i + 1
    
    if (verbose) {
      if (class=="variety") {
        print(paste(i, author, variety))
      } else {
        print(paste(i, author, gender))
      }
    }
  }
  
  return (bow)
}



# GENERATE VOCABULARY
vocabulary <- GenerateVocabulary(path_training, n, swlang=lang)

# GENDER IDENTIFICATION
#######################
# GENERATING THE BOW FOR THE GENDER SUBTASK FOR THE TRAINING SET
bow_training_gender <- GenerateBoW(path_training, vocabulary, class="gender")

# PREPARING THE VECTOR SPACE MODEL FOR THE TRAINING SET
training_gender <- concat.split(bow_training_gender, "V1", ",")
training_gender <- cbind(training_gender[,2], training_gender[,4:ncol(training_gender)])
training_gender$total = rowSums(training_gender[ , 2:ncol(training_gender)])
names(training_gender)[1] <- "theclass"

training_male<-training_gender[which(training_gender$theclass=="male")]
min_male<-min(training_male$total)
max_male<-max(training_male$total)
mean_male<-mean(training_male$total)

training_female<-training_gender[which(training_gender$theclass=="female")]
min_female<-min(training_female$total)
max_female<-max(training_female$total)
mean_female<-mean(training_female$total)

training_gender$dist_max_male<-training_gender$total - max_male
training_gender$dist_max_female<-training_gender$total - max_female
training_gender$dist_min_male<-training_gender$total - min_male
training_gender$dist_min_female<-training_gender$total - min_female
training_gender$dist_mean_male<-training_gender$total - mean_male
training_gender$dist_mean_female<-training_gender$total - mean_female


# Learning a SVM and evaluating it with k-fold cross-validation
train_control <- trainControl( method="repeatedcv", number = k , repeats = r, savePredictions='final', classProbs=T)
#model_SVM_gender <- train( theclass~., data= training_gender, trControl = train_control, method = "svmLinear")
#print(model_SVM_gender)

#model_RANDOM_gender <- train( theclass~., data= training_gender, trControl = train_control, method = "rf")
#print(model_RANDOM_gender)



model_RANGER_gender <- train(theclass~ total+dist_mean_female+dist_mean_male+dist_min_male+dist_min_female+dist_max_female+dist_max_male, data= training_gender, trControl = train_control, method = "ranger")
print(model_RANGER_gender)

#prob_ranger<- model_RANGER_gender$prob
# Learning a SVM with the whole training set and without evaluating it
#train_control <- trainControl(method="none") #### si no quisiesemos hacer validación cruzada####
#model_SVM_gender <- train( theclass~., data= training_gender, trControl = train_control, method = "svmLinear")

# GENERATING THE BOW FOR THE GENDER SUBTASK FOR THE TEST SET
bow_test_gender <- GenerateBoW(path_test, vocabulary, class="gender")

# Preparing the vector space model and truth for the test set
test_gender <- concat.split(bow_test_gender, "V1", ",")
truth_gender <- unlist(test_gender[,2])
test_gender <- test_gender[,4:ncol(test_gender)]
test_gender$total <- rowSums(test_gender[ , 1:ncol(test_gender)])
head(test_gender)

test_gender$dist_max_male<-test_gender$total - max_male
test_gender$dist_max_female<-test_gender$total - max_female
test_gender$dist_min_male<-test_gender$total - min_male
test_gender$dist_min_female<-test_gender$total - min_female
test_gender$dist_mean_male<-test_gender$total - mean_male
test_gender$dist_mean_female<-test_gender$total - mean_female



# Predicting and evaluating the prediction
#pred_SVM_gender <- predict(model_SVM_gender, test_gender)
#confusionMatrix(pred_SVM_gender, truth_gender)

#pred_RANDOM_gender <- predict(model_RANDOM_gender, test_gender)
#confusionMatrix(pred_RANDOM_gender, truth_gender)

pred_RANGER_gender <- predict(model_RANGER_gender, test_gender)
confusionMatrix(pred_RANGER_gender, truth_gender)
