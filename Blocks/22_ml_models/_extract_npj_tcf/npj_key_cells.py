# ==== cell 0 ====
import numpy as np
import pandas as pd
import warnings
import time
from datetime import datetime

from sklearn.impute import KNNImputer
from sklearn.model_selection import RandomizedSearchCV
from sklearn.preprocessing import StandardScaler
import shap
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import roc_auc_score, auc, roc_curve
from sklearn.linear_model import LinearRegression 
from sklearn.experimental import enable_iterative_imputer
from sklearn.impute import IterativeImputer
from sklearn.neighbors import KNeighborsRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.linear_model import Lasso
from sklearn.decomposition import PCA
from sklearn.preprocessing import MinMaxScaler
from sklearn.tree import DecisionTreeClassifier
from sklearn.feature_selection import RFE
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LogisticRegression
from sklearn.feature_selection import mutual_info_regression
from sklearn.metrics import accuracy_score

from sklearn.metrics import precision_score, confusion_matrix, recall_score, f1_score, classification_report, roc_auc_score
from sklearn.preprocessing import MinMaxScaler

import joblib
from collections import Counter
from sklearn.utils import resample
from sklearn.datasets import make_classification

import xgboost as xgb
from xgboost import plot_importance, plot_tree
from sklearn import metrics
from xgboost.sklearn import XGBClassifier

import lightgbm as lgb
from lightgbm import LGBMClassifier

from imblearn.over_sampling import SMOTE
from sklearn.model_selection import learning_curve
import pickle
from sklearn.svm import SVC
from sklearn.naive_bayes import BernoulliNB
from sklearn.ensemble import AdaBoostClassifier
from sklearn.ensemble import GradientBoostingClassifier


import warnings
warnings.filterwarnings("ignore", category=Warning)

import matplotlib.pyplot as plt
from matplotlib import rcParams
import seaborn as sns
from scipy.stats import norm


#显示所有列，把行显示设置成最大
pd.set_option('display.max_columns', 500)

# ==== cell 16 ====
def calculate_entropy(series):
    value_counts = series.value_counts(normalize=True, dropna=False)
    entropy = -(value_counts * np.log2(value_counts + 1e-10)).sum()
    return entropy

feature_entropies = model_data.drop(['是否在28天内死亡','就诊标识（医渡云计算）'],axis=1).apply(calculate_entropy)


# ==== cell 22 ====
scaler_important = MinMaxScaler()
X_train_scaler = scaler_important.fit_transform(X_model)

# ==== cell 23 ====
smote = SMOTE(sampling_strategy=1,k_neighbors=20)
X_resampled, y_resampled = smote.fit_resample(X_train_scaler, y_model)

# ==== cell 42 ====
gb_clf = GradientBoostingClassifier()


param_grid = {
    'n_estimators': np.arange(10,100,10),
    'learning_rate': np.arange(0.01,0.1,10),
    'max_depth': np.arange(2,20,1),
    'subsample':[0.4,0.5,0.6,0.7,0.8],
    'min_samples_split':np.arange(2,20,2),
    'min_samples_leaf':np.arange(20,50,5),
    'max_features':['sqrt','log2']
    }


random_search_gbdt = RandomizedSearchCV(estimator = gb_clf, param_distributions=param_grid, scoring='roc_auc', cv=5)
random_search_gbdt.fit(X_resampled, y_resampled)

best_n_estimators = random_search_gbdt.best_params_['n_estimators']
best_learning_rate = random_search_gbdt.best_params_['learning_rate']
best_max_depth = random_search_gbdt.best_params_['max_depth']
best_subsample = random_search_gbdt.best_params_['subsample']
best_min_samples_split = random_search_gbdt.best_params_['min_samples_split']
best_min_samples_leaf = random_search_gbdt.best_params_['min_samples_leaf']
best_max_features = random_search_gbdt.best_params_['max_features']

print('best_n_estimators:',best_n_estimators)
print('best_learning_rate:',best_learning_rate)
print('best_max_depth:',best_max_depth)
print('best_subsample:',best_subsample)
print('best_min_samples_split:',best_min_samples_split)
print('best_min_samples_leaf:',best_min_samples_leaf)
print('best_max_features:',best_max_features)

# ==== cell 43 ====
model_gbdt_result = GradientBoostingClassifier(n_estimators = best_n_estimators,
                                                learning_rate = best_learning_rate,
                                                max_depth = best_max_depth,
                                                subsample = best_subsample,
                                                min_samples_split = best_min_samples_split,
                                                min_samples_leaf = best_min_samples_leaf,
                                                max_features = best_max_features)
model_gbdt_result.fit(X_resampled, y_resampled)

# ==== cell 47 ====
def topsis(data, weight=None):
 
    Z = pd.DataFrame([data.max(), data.min()], index=['正理想解', '负理想解'])
 
    weight = entropyWeight(data) if weight is None else np.array(weight)
    Result = data.copy()
    Result['正理想解'] = np.sqrt(((data - Z.loc['正理想解']) ** 2 * weight).sum(axis=1))
    Result['负理想解'] = np.sqrt(((data - Z.loc['负理想解']) ** 2 * weight).sum(axis=1))
 
    Result['综合得分指数'] = Result['负理想解'] / (Result['负理想解'] + Result['正理想解'])  
    Result['排序'] = Result.rank(ascending=False)['综合得分指数']
 
    return Result, Z, weight
 
weight = [1/6,1/6,1/6,1/6,1/6,1/6,]
Result, Z, weight = topsis(results_1, weight)

# ==== cell 48 ====
def mult_model(data):

    result = pd.DataFrame()

    y_pred_tree = model_tree_result.predict(data)
    y_proba_tree = model_tree_result.predict_proba(data)[:,1]

    y_pred_rf = model_rf_result.predict(data)
    y_proba_rf = model_rf_result.predict_proba(data)[:,1]   

    y_pred_xgb = model_xgb_result.predict(data)
    y_proba_xgb = model_xgb_result.predict_proba(data)[:,1] 

    y_pred_lgb = model_lgb_result.predict(data)
    y_proba_lgb = model_lgb_result.predict_proba(data)[:,1] 

    y_pred_svm = model_svm_result.predict(data)
    y_proba_svm = model_svm_result.predict_proba(data)[:,1] 

    y_pred_nb = model_nb_result.predict(data)
    y_proba_nb = model_nb_result.predict_proba(data)[:,1]      

    y_pred_gbdt = model_gbdt_result.predict(data)
    y_proba_gbdt = model_gbdt_result.predict_proba(data)[:,1]
   
    result['y_probas'] = y_proba_tree*0.141+y_proba_rf*0.153+y_proba_xgb*0.155+y_proba_lgb*0.151+y_proba_svm*0.089+y_proba_nb*0.153+y_proba_gbdt*0.158
 
    result.loc[result['y_probas'] <= 0.5,'y_pred'] = np.int(0)
    result.loc[result['y_probas']  > 0.5,'y_pred'] = np.int(1)

    return result
